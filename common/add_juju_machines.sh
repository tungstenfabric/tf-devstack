#!/bin/bash
# Adds NUMBER_OF_MACHINES_TO_DEPLOY instances

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# parameters
NUMBER_OF_MACHINES_TO_DEPLOY=${NUMBER_OF_MACHINES_TO_DEPLOY:-1}

# add machines
juju add-machine -n $NUMBER_OF_MACHINES_TO_DEPLOY --constraints "mem=15G cores=2 root-disk=80G" 2>&1

# wait for machines are ready
sleep 30
JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
for machine in $JUJU_MACHINES ; do
    echo "Waiting for machine: $machine"
    fail=0
    while ! output=`juju ssh $machine "uname -a" 2>/dev/null` ; do
        if ((fail >= 60)); then
            echo "ERROR: Machine $machine did not up."
            echo $output
            exit 1
        fi
        sleep 10
        ((++fail))
    done
done
