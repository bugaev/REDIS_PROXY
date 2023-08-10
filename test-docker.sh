#!/usr/bin/env bash
#vim: ts=4:sw=4

set -euo pipefail

trap 'catch $? $LINENO' ERR

catch() {
  echo "$0: Error $1 occurred on $2"
}

DEBUG=no

function test_redis_alive {
	message "TODO: Redis is alive"
}

function waitForRedis {
	local timeout=$1
	local host=$2
	local port=$3
	local cnt=0
	while ((cnt < timeout))
	do
		if redis-cli -h $host -p $port PING | grep -q PONG
		then
			echo 'Redis is alive.'
			return 0
		fi
		sleep 1s
		cnt=$((cnt + 1))
		echo "Waiting for Redis: $cnt/$timeout"
	done
}


function waitForProxy {
	local timeout=$1
	local host=$2
	local port=$3
	local cnt=0
	while ((cnt < timeout))
	do
		if curl proxy:5001/ItsAlwaysSunnyInPhiladelphia 2>/dev/null | grep -q None
		then
			echo 'Proxy is alive.'
			return 0
		fi
		sleep 1s
		cnt=$((cnt + 1))
		echo "Waiting for proxy: $cnt/$timeout"
	done
}


function message {
    echo ""
    echo "---------------------------------------------------------------"
    echo $1
    echo "---------------------------------------------------------------"
}

RESTORE=$(echo -en '\033[0m')
RED=$(echo -en '\033[01;31m')
GREEN=$(echo -en '\033[01;32m')

function failed {
    echo ${RED}✗$1${RESTORE}
}

function passed {
    echo ${GREEN}✓$1${RESTORE}
}

function abspardir {
	if cd $(dirname "$1") &> /dev/null
	then
		pwd
		cd - &> /dev/null
	else
		echo None
	fi
}

SCRIPT_DIR="$(abspardir "$0")"


POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		--debug)
			DEBUG=yes
			shift # past argument
		;;
		*) # unknown option
			POSITIONAL+=("$1") # save it in an array for later
			shift # past argument
		;;
  esac
done

if [[ ${#POSITIONAL[@]} -gt 0 ]]
then
	set -- "${POSITIONAL[@]}" # restore positional parameters
fi

if [[ ${#POSITIONAL[@]} -gt 0 ]]
then
	echo "Unknown arguments: ${POSITIONAL[@]}"
	exit 1
fi

if [[ "$DEBUG" == "yes" ]]
then
	set -x
fi


message "Waiting for dependencies..."
waitForRedis 20 $REDIS_HOST $REDIS_PORT

# "$SCRIPT_DIR/set-redis-test-data.sh" --host $REDIS_HOST --port $REDIS_PORT >/dev/null

waitForProxy 20 $PROXY_HOST $PROXY_PORT

FAIL_CNT=0

message test-denied-concurrent-above-limit.sh

if "$SCRIPT_DIR/test-denied-concurrent-above-limit.sh" --host $PROXY_HOST --port $PROXY_PORT --redis-host $REDIS_HOST --redis-port $REDIS_PORT --ttl $TTL --conn-limit $MAX_CONN --above-limit 5
then
	passed test-denied-concurrent-above-limit.sh
else
	failed test-denied-concurrent-above-limit.sh
	FAIL_CNT=$((FAIL_CNT + 1))
fi

message test-ttl.sh

if "$SCRIPT_DIR/test-ttl.sh" --host $PROXY_HOST --port $PROXY_PORT --redis-host $REDIS_HOST --redis-port $REDIS_PORT --ttl $TTL
then
	passed test-ttl
else
	failed test-ttl
	FAIL_CNT=$((FAIL_CNT + 1))
fi

message test-redis-protocol.sh

if "$SCRIPT_DIR/test-redis-protocol.sh" --host $PROXY_HOST --port $TCP_PORT --redis-host $REDIS_HOST --redis-port $REDIS_PORT
then
	passed test-redis-protocol.sh
else
	failed test-redis-protocol.sh
	FAIL_CNT=$((FAIL_CNT + 1))
fi



message test-served-all-concurrent-below-limit.sh

if "$SCRIPT_DIR/test-served-all-concurrent-below-limit.sh" --host $PROXY_HOST --port $PROXY_PORT --redis-host $REDIS_HOST --redis-port $REDIS_PORT --ttl $TTL --conn-limit $MAX_CONN
then
	passed test-served-all-concurrent-below-limit.sh
else
	failed test-served-all-concurrent-below-limit.sh
	FAIL_CNT=$((FAIL_CNT + 1))
fi

message test-lru.sh

if "$SCRIPT_DIR/test-lru.sh" --host $PROXY_HOST --port $PROXY_PORT --redis-host $REDIS_HOST --redis-port $REDIS_PORT --capacity $CACHE_SIZE
then
	passed test-lru
else
	failed test-lru
	FAIL_CNT=$((FAIL_CNT + 1))
fi




message "TEST SUMMARY"

if [[ $FAIL_CNT -eq 0 ]]
then
	passed "Success: all tests passed."
else
	failed "$FAIL_CNT tests failed out of 5."	
fi


exit 0
