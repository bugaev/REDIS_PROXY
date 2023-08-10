#!/usr/bin/env bash
# vim: ts=4:sw=4

# `test-denied-concurrent-above-limit.sh` return HTTP status code 503 for connections above the limit.

# Using Redis' command
# ```
# CLIENT PAUSE <time to wait>
# ```
# to create a build-up of client requests to the Proxy.  Proxy is waiting until a
# connection with the backing server is established while the test script sends a
# number of asynchronous requests.  If the number of requests is above the
# maximal number of allowed concurrent connections, the excess above the limit
# will have HTTP status code 503.  Verifying that the number of rejected requests
# is equal to the excess.

set -euo pipefail

DEBUG=no
DRY_RUN=no
REDIS_PAUSE=2 # Seconds.
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
		-l|--conn-limit)
			LIMIT="$2"
			shift # past argument
			shift # past value
		;;
		-a|--above-limit)
			DELTA_LIMIT="$2"
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
if [[ "x$LIMIT" == x ]]
then
	echo "$0 ERROR: -l|--conn-limit is not given."
	exit 1
fi

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


OUT_ASYNC="$SCRIPT_DIR/OUT_ASYNC"
mkdir -p "$OUT_ASYNC"
rm -f "$OUT_ASYNC/"*.txt

TTL_PLUS_1=$((TTL + 1))
LIMIT_PLUS_DELTA=$((LIMIT + DELTA_LIMIT))

# Make sure that all entries in cache have expired (important):
sleep $TTL_PLUS_1

$SCRIPT_DIR/set-redis-test-data.sh --host $REDIS_HOST --port $REDIS_PORT --limit $LIMIT_PLUS_DELTA > /dev/null

# Pause Redis:
redis-cli -h $REDIS_HOST -p $REDIS_PORT client pause ${REDIS_PAUSE}000 &> /dev/null

for i in $(seq 1 $LIMIT_PLUS_DELTA)
do
	$SCRIPT_DIR/get-key-proxy-http.sh --key i$i --host $HOST_NAME --port $HOST_PORT --dst "$OUT_ASYNC" &
done

# Wait for Redis to wake up and unblock :
REDIS_PAUSE_PLUS_1=$((REDIS_PAUSE + 1))
sleep $REDIS_PAUSE_PLUS_1

# Number of requests denied.  It should equal to DELTA_LIMIT:
denied=0
for i in $(seq 1 $LIMIT_PLUS_DELTA)
do
	test_out="$OUT_ASYNC/i$i.txt"
	test -f "$test_out" || exit 1
	read -r line < "$test_out"
	if echo $line | grep -q 'Number of connections reached its maximum'
	then
		denied=$((denied + 1))
	fi
done

if [[ $denied -ne $DELTA_LIMIT ]]
then
	echo "ERROR: number of denied requests $denied doesn't match the excess $DELTA_LIMIT"
	exit 1
fi


