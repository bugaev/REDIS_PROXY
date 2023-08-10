#!/usr/bin/env bash
# vim: ts=4:sw=4

set -euo pipefail

LIMIT=9
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

set -u


$SCRIPT_DIR/set-redis-test-data.sh --host $REDIS_HOST --port $REDIS_PORT --limit 9 > /dev/null

knownVal=$(redis-cli -h $HOST_NAME -p $HOST_PORT get i7)
if [[ "$knownVal" != "7" ]]
then
	echo "Returned value $knownVal  doesn't match 7"
	exit 1
fi

unknownVal=$(redis-cli -h $HOST_NAME -p $HOST_PORT get ItsAlwaysSunnyInPhiladelphia)
# redis-cli -h $HOST_NAME -p $HOST_PORT get ItsAlwaysSunnyInPhiladelphia &> tmp.txt
if [[ "$unknownVal" != "" ]]
# if [[ "$unknownVal" != "(nil)" ]]
then
	echo "Returned value >$unknownVal< doesn't match (nil)"
	exit 1
fi
