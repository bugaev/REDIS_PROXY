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

SCRIPT_DIR=$(dirname $(realpath $0))
# If realpath is not in the system:
# SCRIPT_DIR="$(abspardir "$0")"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-d|--dst)
			OUT_ASYNC="$2"
			shift # past argument
			shift # past value
		;;
		-k|--key)
			KEY="$2"
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
if [[ "x$KEY" == x ]]
then
	echo "$0 ERROR: -k|--key is not given."
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

if [[ "x$OUT_ASYNC" == x ]]
then
	echo "$0 ERROR: -d|--dst is not given."
	exit 1
fi
set -u
if [[ $DEBUG == yes ]]
then
	set -x
fi
# curl -silent "$HOST_NAME:$HOST_PORT/$KEY" -o $OUT_ASYNC/$KEY.txt
# I have to use /dev/null here as a workaround for an unexpected side effect of -silent: 
# in addition to suppression of the progress bar, curl writes the header to the output file.
curl "$HOST_NAME:$HOST_PORT/$KEY" -o $OUT_ASYNC/$KEY.txt 2>/dev/null

