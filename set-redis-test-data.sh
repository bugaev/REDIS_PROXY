#!/usr/bin/env bash
# vim: ts=4:sw=4

# TODO: Make flushdb work with database number. Currently, it fails with exit code 1.

set -euo pipefail


trap 'catch $? $LINENO' ERR

catch() {
  echo "Error $1 occurred on $2"
}

DBNO=9
DEBUG=no
#REDIS_CLI="redis-cli -n $DBNO"
REDIS_CLI="redis-cli"

SCRIPT_DIR=$(dirname $(realpath $0))
POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		--debug)
			DEBUG=yes
			shift # past argument
		;;
		-h|--host)
			REDIS_HOST=$2
			shift # past argument
			shift # past value
		;;
		-p|--port)
			REDIS_PORT=$2
			shift # past argument
			shift # past value
		;;
		-l|--limit)
			LIMIT=$2
			shift # past argument
			shift # past value
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


set +u
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

if [[ "x$LIMIT" == x ]]
then
	echo "$0 ERROR: -l|--limit is not given."
	exit 1
fi
set -u

$REDIS_CLI -h $REDIS_HOST -p $REDIS_PORT flushdb 1>/dev/null

for i in $(seq 0 $LIMIT)
do
	$REDIS_CLI -h $REDIS_HOST -p $REDIS_PORT set i$i $i 1>/dev/null
done

# $REDIS_CLI -h $REDIS_HOST -p $REDIS_PORT < "$SCRIPT_DIR"/test-integers.txt
# $REDIS_CLI -h $REDIS_HOST -p $REDIS_PORT < "$SCRIPT_DIR"/test-strings1.txt
# $REDIS_CLI -h $REDIS_HOST -p $REDIS_PORT < "$SCRIPT_DIR"/test-lists.txt
