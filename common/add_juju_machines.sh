#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"

# Adds CONTROLLER_NODES to model for manual deployment
if [[ $CLOUD == 'manual']] ; then
    if [[ -n "$CONTROLLER_NODES" || -n "$AGENT_NODES" ]]; then
        for node in $CONTROLLER_NODES $AGENT_NODES ; do
            if [[ $node != $NODE_IP && $CLOUD == 'manual' ]]; then
                juju add-machine ssh:ubuntu@$node
            fi
        done
    fi
elif [[ $CLOUD == 'aws' && $ORCHESTRATOR == 'all' ]] ; then
    juju add-machine --series=$UBUNTU_SERIES --constraints "mem=7G cores=4 root-disk=40G"
fi
