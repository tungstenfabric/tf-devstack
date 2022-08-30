#!/bin/bash

exec 3>&1 1> >(tee /tmp/set_timeserver.log) 2>&1

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

[[ "$DEBUG" == true ]] && set -x

if [[ -n "$NTP_SERVERS" ]]; then
    if [[ -e $my_dir/functions.sh ]]; then
        source $my_dir/functions.sh
        ensure_timeserver "$NTP_SERVERS"
    else
        echo "ERROR: file $my_dir/functions.sh not found. Exiting"
        exit 1
    fi
else
    echo "ERROR: Variable NTP_SERVERS is undefined. Exiting"
    exit 1
fi

fi

