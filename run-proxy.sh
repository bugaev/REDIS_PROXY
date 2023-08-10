#!/usr/bin/env bash
# vim: ts=4:sw=4
# set -x

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

# If realpath is not in the system:
SCRIPT_DIR="$(abspardir "$0")"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-h|--proxy-host)
			FLASK_HOST="$2"
			shift # past argument
			shift # past value
		;;
		-p|--proxy-port)
			FLASK_PORT="$2"
			shift # past argument
			shift # past value
		;;
		-rh|--redis-host)
			REDIS_HOST="$2"
			shift # past argument
			shift # past value
		;;
		-rp|--redis-port)
			REDIS_PORT="$2"
			shift # past argument
			shift # past value
		;;
		-th|--tcp-host)
			TCP_HOST="$2"
			shift # past argument
			shift # past value
		;;
		-tp|--tcp-port)
			TCP_PORT="$2"
			shift # past argument
			shift # past value
		;;
		-c|--cache-size)
			CACHE_SIZE="$2"
			shift # past argument
			shift # past value
		;;
		-m|--max-connections)
			MAX_CONN="$2"
			shift # past argument
			shift # past value
		;;
		-t|--ttl)
			TTL="$2"
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

function help {
	echo "All (and only) parameters below should be specified:"
	echo "-h|--proxy-host
-p|--proxy-port
-rh|--redis-host
-rp|--redis-port
-th|--tcp-host
-tp|--tcp-port
-c|--cache-size
-m|--max-connections
-t|--ttl"

}

if [[ ${#POSITIONAL[@]} -gt 0 ]]
then
	set -- "${POSITIONAL[@]}" # restore positional parameters
fi

if [[ ${#POSITIONAL[@]} -gt 0 ]]
then
	echo "Unknown arguments: ${POSITIONAL[@]}"
	exit 1
fi

if [ -z ${FLASK_HOST+x} ]
then
	echo "ERROR: -h|--proxy-host is not given."
	help
	exit 1
fi

if [ -z ${FLASK_PORT+x} ]
then
	echo "ERROR: -p|--proxy-port is not given."
	help
	exit 1
fi


if [ -z ${REDIS_HOST+x} ]
then
	echo "ERROR: -rh|--redis-host is not given."
	help
	exit 1
fi

if [ -z ${REDIS_PORT+x} ]
then
	echo "ERROR: -rp|--redis-port is not given."
	help
	exit 1
fi

if [ -z ${TCP_HOST+x} ]
then
	echo "ERROR: -th|--tcp-host is not given."
	help
	exit 1
fi

if [ -z ${TCP_PORT+x} ]
then
	echo "ERROR: -tp|--tcp-port is not given."
	help
	exit 1
fi

if [ -z ${CACHE_SIZE+x} ]
then
	echo "ERROR: -c|--cache-size is not given."
	help
	exit 1
fi


if [ -z ${MAX_CONN+x} ]
then
	echo "ERROR: -m|--max-connections is not given."
	help
	exit 1
fi

if [ -z ${TTL+x} ]
then
	echo "ERROR: -m|--max-connections is not given."
	help
	exit 1
fi


if [[ $DEBUG == yes ]]
then
  set -x
fi
docker run  -p $FLASK_PORT:$FLASK_PORT/tcp  -p $TCP_PORT:$TCP_PORT/tcp --rm --name cust-python -it -e CACHE_SIZE=$CACHE_SIZE -e MAX_CONN=$MAX_CONN -e REDIS_HOST=$REDIS_HOST -e REDIS_PORT=$REDIS_PORT -e FLASK_HOST=$FLASK_HOST -e FLASK_PORT=$FLASK_PORT -e TTL=$TTL -e TCP_HOST=$TCP_HOST -e TCP_PORT=$TCP_PORT redis_proxy_proxy pipenv run python proxy.py
