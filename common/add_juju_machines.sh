#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# parameters
ORCHESTRATOR=${ORCHESTRATOR:-'openstack'}
CLOUD=${CLOUD:-'aws'}
CONTROLLER_NODES=${CONTROLLER_NODES:-}

# add machines
if [[ $CLOUD == 'manual' ]]; then
    for machine in `echo $CONTROLLER_NODES | tr ',' ' '` ; do
        juju add-machine ssh:ubuntu@$machine 2>&1
    done
else
    juju add-machine -n 4 --constraints "mem=15G cores=2 root-disk=80G" 2>&1
fi

JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`

if [[ $CLOUD != "manual"* ]] ; then
    # wait for machines are ready
    sleep 30
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
fi

if [[ $ORCHESTRATOR == 'openstack' && $CLOUD != "manual" ]] ; then #TODO
    # fix lxd profile
    for machine in $JUJU_MACHINES ; do
        juju scp "$my_dir/../juju/lxd-default.yaml" $machine:lxd-default.yaml 2>/dev/null
        juju ssh $machine "cat ./lxd-default.yaml | sudo lxc profile edit default"
    done
fi
