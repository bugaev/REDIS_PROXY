#!/usr/bin/env bash
# vim: ts=4:sw=4

# `test-lru.sh`: LRU eviction of cache keys.
# Requesting more keys than the cache
# capacity.  The earliest keys get evicted and get updated with new values from
# the backing database.  Verifying that update happened to the earliest keys
# and didn't happen to more recent ones.

set -euo pipefail

DEBUG=no
DRY_RUN=no
trap 'catch $? $LINENO' ERR

catch() {
  echo "$0: Error $1 occurred on $2"
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

SCRIPT_DIR=$(dirname $(realpath $0))
# If realpath is not in the system:
# SCRIPT_DIR="$(abspardir "$0")"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-c|--capacity)
			CAPACITY="$2"
			shift # past argument
			shift # past value
		;;
		-h|--host)
			HOST_NAME="$2"
			shift # past argument
			shift # past value
		;;
		-p|--port)
			HOST_PORT="$2"
			shift # past argument
			shift # past value
		;;
		-rh|--redis-host)
			REDIS_HOST=$2
			shift # past argument
			shift # past value
		;;
		-rp|--redis-port)
			REDIS_PORT=$2
			shift # past argument
			shift # past value
		;;
		--debug)
			DEBUG=yes
			shift # past argument
		;;
		--dry-run)
			DRY_RUN=yes
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

set +u
if [[ "x$HOST_NAME" == x ]]
then
	echo "$0 ERROR: -h|--host is not given."
	exit 1
fi

if [[ "x$HOST_PORT" == x ]]
then
	echo "$0 ERROR: -p|--port is not given."
	exit 1
fi

if [[ "x$REDIS_HOST" == x ]]
then
	echo "$0 ERROR: -h|--host is not given."
	exit 1
fi

if [[ "x$REDIS_PORT" == x ]]
then
	echo "$0 ERROR: -p|--port is not given."
	exit 1
fi

if [[ "x$CAPACITY" == x ]]
then
	echo "$0 ERROR: -c|--capacity is not given."
	exit 1
fi
set -u

# OUT_ASYNC="$SCRIPT_DIR/OUT_ASYNC"

CAPACITY_PLUS_1=$((CAPACITY + 1))

$SCRIPT_DIR/set-redis-test-data.sh --host $REDIS_HOST --port $REDIS_PORT --limit $CAPACITY_PLUS_1 > /dev/null

for i in $(seq 1 $CAPACITY)
do
	curl "$HOST_NAME:$HOST_PORT/i$i" 2>/dev/null 1>/dev/null
done

curl "$HOST_NAME:$HOST_PORT/i$CAPACITY_PLUS_1" 2>/dev/null 1>/dev/null
redis-cli -h $REDIS_HOST -p $REDIS_PORT flushdb > /dev/null


# These keys stay in cache:
for i in $(seq 2 $CAPACITY_PLUS_1)
do
	curl_val="$(curl "$HOST_NAME:$HOST_PORT/i$i" 2>/dev/null)"

	if [[ $curl_val != $i ]]
	then
		echo "Entry $i doesn't match $i: $curl_val"
		exit 1
	fi
done

# This key is supposed to be evicted. The returned value should be the None since I cleared the Redis database:
curl_val="$(curl -s "$HOST_NAME:$HOST_PORT/i0" 2>/dev/null)"
if [[ $curl_val != None ]]
then
	echo "Entry $i doesn't match $i: $curl_val"
	exit 1
fi
