#!/usr/bin/env bash
# vim: ts=4:sw=4

# `test-ttl.sh`: Expiraton of cache keys
# Refreshing the backing database, waiting for a period > TTL until values expire. Verifying that a new request
# fetches new values from Redis and not old values from the cache.

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
		-t|--ttl)
			TTL=$2
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

if [[ "x$TTL" == x ]]
then
	echo "$0 ERROR: -t|--ttl is not given."
	exit 1
fi

set -u

TTL_PLUS_1=$((TTL + 1))

sleep $TTL_PLUS_1

$SCRIPT_DIR/set-redis-test-data.sh --host $REDIS_HOST --port $REDIS_PORT --limit 99 > /dev/null

# Fetching either the first time or after cache expiry so that we update the cache with a fresh value:
curl "$HOST_NAME:$HOST_PORT/i7" 2>/dev/null 1>/dev/null

redis-cli -h $REDIS_HOST -p $REDIS_PORT flushdb > /dev/null

sleep $TTL_PLUS_1


# This key is supposed to expire. The returned value should be None since I cleared the Redis database:
curl_val="$(curl -s "$HOST_NAME:$HOST_PORT/i7" 2>/dev/null)"
if [[ $curl_val != None ]]
then
	echo "Entry doesn't match None: $curl_val"
	exit 1
fi
