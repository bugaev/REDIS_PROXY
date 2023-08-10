# High-level architecture overview

The Redis Proxy, or simply the Proxy, is implemented as a service running in a Docker container.  The HTTP service is built with the Flask Python framework running its own production server (as opposed to being a WSGI client).  This allows to additionally run a thread with a TCP server implementing a subset of Redis protocol and having an access to the same cached data as the HTTP server.

Python virtual environment in the image is created identical to the development environment using `Pipenv`.  Enforced with the "--deploy" option, it ensures a reproducibility better than `requirements.txt`.

Originally, the program was implemented with the [safecache](https://github.com/Verizon/safecache "GitHub repo") caching decorator that promised to have implemented LRU and TTL eviction alongside with thread safety.  This implementation of the 3rd party class proved to be faulty.  Instead, I have created my own cache class in the `lru_cache` module.  I added expiry time to this 
[LRU Cache using OrderedDict](https://www.geeksforgeeks.org/lru-cache-in-python-using-ordereddict/amp/ "geeksforgeeks tutorial").


# What the code does

The code builds a Docker image with the Proxy, runs tests on the proxy service in an isolated environment, _not_ interfering with the host network.
The Proxy runs two servers: HTTP and Redis server.  HTTP server responds to HTTP GET requests.  Redis server responds to GET requests using Redis protocol.

Upon startup, the Proxy creates a cache with the capacity or `$CACHE_SIZE`, expiry time `$TTL`.  These parameters, as well as maximal number of concurrent connections `$MAX_CONN` and host addresses and ports are passed as container environment variables.  A convenience wrapper passing all configuration parameters to the Proxy is implemented in `run-proxy.sh`.  An example using the wrapper can be found in "How to run the code".

If a requested key is in the cache and its value didn't expire, the value is served to the client.  If the value has expired or not present in the cache, it is fetched from a backing Redis server.  If the value is not found, the server returns None along with HTTP status code 404.  If, trying to fetch the value from Redis, a connection with the backing Redis server could note be established, HTTP status 503 is returned.


# How to run the code and tests

The archive includes Makefile that builds a Docker image with the Proxy and runs tests on a running container instance.

To build the image and run tests:
```
tar -zxvf REDIS_PROXY.tar.gz
cd REDIS_PROXY
make test
```

The `make` command uses Docker Compose to create an app consisting of three containers based on:
- The official Redis Docker image from the Docker Hub
- The Proxy image built with `Dockerfile` (redis_proxy_proxy)
- The Test image built with `DockerfileTest`


Upon startup of a Test container, the top-level test script `test-docker.sh` is running in the container environment.  All three containers are running in their own network, _not_ interfering with the host.

The top-level test script calls 5 individual scripts verifying particular features of the Proxy.
- `test-lru.sh`: LRU eviction of cache keys
- `test-ttl.sh`: Expiraton of cache keys
- `test-served-all-concurrent-below-limit.sh`: all client requests are served in parallel if number of concurrent connections is within the limit.
- `test-denied-concurrent-above-limit.sh`: if number of simultaneously processed requests exceeds the concurrent client limit, return HTTP status code 503.
- `test-redis-protocol.sh`: Implementation of a subset of Redis protocol.

After the tests are done, the app shuts down, leaving the Proxy image behind.


The Proxy image can be used to start a proxy instance using `run-proxy.sh`.  For example,
```
./run-proxy.sh  --proxy-host '0.0.0.0'  --proxy-port '5001'  --redis-host '192.168.1.69'  --redis-port '6379'  --tcp-host ''  --tcp-port 5010  --cache-size 99  --max-connections 99  --ttl 5
```

To GET a value from the Proxy for the *key* using HTTP:
```
 curl http://127.0.0.1:5001/key
 ```
> key_value

```
 curl http://127.0.0.1:5001/nonexisting_key
 ```
><empty body, HTTP status code 404> 


Using Redis protocol:
```
redis-cli -h 127.0.0.1 -p 5010 GET key
```
> "key_value"

`redis-cli -h 127.0.0.1 -p 5010 GET nonexisting_key`
> (nil)

Building and running tests was verified with `docker compose` v.2.2.3 on both macOS Monterey and CentOS 7.  On Linux, it is important to use `docker compose`, rather than `docker-compose` to ensure the latest version of Docker Compose.

# Algorithmic complexity of the cache operations
The complexity is O(1) since my implementation is based on OrderedDict using hashed string values.

# Tests

## `test-lru.sh` LRU eviction of cache keys
Requesting more keys than the cache capacity.  The earliest keys get evicted and get updated with new values from the backing database.  Verifying that update happened to the earliest keys and didn't happen to more recent ones.

## `test-ttl.sh`: Expiraton of cache keys
Refreshing the backing database, waiting for a period > TTL until values expire. Verifying that a new request fetches new values from Redis and not old values from the cache.

## `test-served-all-concurrent-below-limit.sh` all client requests are served in parallel

... if number of concurrent connections is within the limit.

Using Redis' command
```
CLIENT PAUSE <time to wait>
```
to create a build-up of client requests to the Proxy.  Proxy is waiting until a connection with the backing server is established while the test script sends a number of asynchronous requests.  If the number of requests is below the maximal number of concurrent connections `$MAX_CONN`, all requests will be processed after the connection with Redis is reestablished.

## `test-denied-concurrent-above-limit.sh` return HTTP status code 503

... for connections above the limit.

Using Redis' command
```
CLIENT PAUSE <time to wait>
```
to create a build-up of client requests to the Proxy.  Proxy is waiting until a connection with the backing server is established while the test script sends a number of asynchronous requests.  If the number of requests is above the maximal number of allowed concurrent connections, the excess above the limit will have HTTP status code 503.  Verifying that the number of rejected requests is equal to the excess.

