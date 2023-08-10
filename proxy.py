#!/usr/bin/env python3.8

import redis
import os
import sys
import time
import socket
# from safecache import safecache
from flask import Flask
from flask import abort
from flask import make_response
from threading import Lock
from threading import Thread
sys.path.append(".")
import lru_cache
import re


redis_cmd_rx = re.compile(b'\*2\\r\\n\$3\\r\\n[gG][eE][tT]\\r\\n(.*)\\r\\n(.*)\\r\\n$')

try:
    CACHE_SIZE = int(os.environ['CACHE_SIZE'])
    MAX_CONN = int(os.environ['MAX_CONN'])
    # Real world: REDIS_HOST='192.168.1.69'
    REDIS_HOST = os.environ['REDIS_HOST']
    REDIS_PORT = int(os.environ['REDIS_PORT'])
    FLASK_HOST = str(os.environ['FLASK_HOST'])
    FLASK_PORT = int(os.environ['FLASK_PORT'])
    TTL=int(os.environ['TTL'])
    TCP_HOST = os.environ['TCP_HOST']
    TCP_PORT = int(os.environ['TCP_PORT'])
except Exception as ex: 
    print(ex)
    print(f'ERROR: Not all required env variables are present', file=sys.stderr)
    sys.exit()
DBNO = 0
# print(f'FLASK_APP: {FLASK_APP}')


app = Flask(__name__)
server_address =  (TCP_HOST, TCP_PORT)

lock = Lock()

cache_lock = Lock()
cache = lru_cache.LRUCache(CACHE_SIZE, TTL) 

connCounter = 0

# @safecache(ttl=TTL, maxsize=CACHE_SIZE)
def lookupRedis(key):
    # print(f"quering Redis for {key}...")
    r = redis.Redis(host=REDIS_HOST, db=DBNO)

    retries = 20
    while True:
        try:
            return True, r.get(str(key)) 
        except redis.exceptions.ConnectionError as exc:
            if retries == 0:
                return False, None
            print(f'INFO: reconnecting to Redis', file=sys.stderr)
            retries -= 1
            time.sleep(1)
    
def lookupRedisCustom(key):
    # print(f"quering Redis for {key}...")
    r = redis.Redis(host=REDIS_HOST, db=DBNO)

    retries = 20
    while True:
        try:
            return True, r.get(str(key)) 
        except redis.exceptions.ConnectionError as exc:
            if retries == 0:
                return False, None
            print(f'INFO: reconnecting to Redis', file=sys.stderr)
            retries -= 1
            time.sleep(1)

@app.route("/buggy/<key>")
def buggyRoute(key):
    global connCounter
    try:
        with lock:
            connCounter = connCounter + 1
            if connCounter > MAX_CONN:
                # print(f'Max connections reached: {key}\n')
                return 'Number of connections reached its maximum.\n', 503
        begin = time.time()
        print(f'--------- PROCESSING BUGGY REQUEST FOR {key}. Connections: {connCounter} ----------\n', file=sys.stderr)
        # time.sleep(3)
        success, redisVal = lookupRedis(key)
        end = time.time()
        print(f'time elapsed: {end - begin}')
        if success:
            if redisVal:
                return redisVal + b'\n'
            else:
                return b'None\n', 404
        else:
            return 'Backing Redis server not available.\n', 503 
    finally:
        with lock:
            connCounter = connCounter - 1
        print(f'--------- ENDING BUGGY REQUEST FOR {key}. Connections: {connCounter} ----------\n', file=sys.stderr)

@app.route("/<key>")
def lookupKey(key):
    global connCounter
    try:
        with lock:
            connCounter = connCounter + 1
            if connCounter > MAX_CONN:
                # print(f'Max connections reached: {key}\n')
                return 'Number of connections reached its maximum.\n', 503
        begin = time.time()
        print(f'--------- PROCESSING FAST REQUEST FOR {key}. Connections: {connCounter} ----------\n', file=sys.stderr)
        with cache_lock:
            cached = cache.get(key)
            if cached:
                redisVal, cached_time = cached
                if cached_time < time.time():
                    success, redisVal = lookupRedisCustom(key)
                    if success:
                        cache.put(key, redisVal)
                    else:
                        # Leave the old time so that next attempt can invalidate the entry:
                        # For now, redisVal == None
                        pass
                else:
                    success = True
            else:
                success, redisVal = lookupRedisCustom(key)
                if success:
                    cache.put(key, redisVal)
                
        end = time.time()
        print(f'time elapsed: {end - begin}', file=sys.stderr)
        if success:
            if redisVal:
                return redisVal + b'\n'
            else:
                return b'None\n', 404
        else:
            return 'Backing Redis server not available.\n', 503 
    finally:
        with lock:
            connCounter = connCounter - 1
        print(f'--------- ENDING FAST REQUEST FOR {key}. Connections: {connCounter} ----------\n', file=sys.stderr)

def launch_socket_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(server_address)
    sock.listen(1)
    print('Listening...')

    while True:
        #Wait for connection
        connection, address = sock.accept()
        # connection.settimeout(9.0)
        print('Connected', address)
        try:
            #Receive data
            while True:
                data = connection.recv(1024)
                if not data:
                    break
                print(data)
                match = redis_cmd_rx.match(data)
                key = None
                if match:
                    # print(f'groups: {match.groups()}')
                    # print(match.groups(1))
                    key = match.group(2)
                    r = redis.Redis(host=REDIS_HOST, db=DBNO)
                    redisVal = r.get(key)
                if redisVal:
                    connection.sendall(b'$' + str(len(redisVal)).encode() + b'\r\n' + redisVal + b'\r\n')
                else:
                    connection.sendall(b"$-1\r\n")
        finally:
            #Clean up connection
            connection.close()

if __name__ == "__main__":
    t = Thread(target=launch_socket_server)
    t.daemon = True
    t.start()

    app.run(debug=False, host=FLASK_HOST, port=FLASK_PORT, use_reloader=False)

