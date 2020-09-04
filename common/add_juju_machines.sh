#!/bin/bash

# Adds CONTROLLER_NODES and AGENT_NODES to model for manual deployment

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"

if [[ -n "$CONTROLLER_NODES" || -n "$AGENT_NODES" ]]; then
    for node in $CONTROLLER_NODES ; do
        if [[ $node != $NODE_IP && $CLOUD == 'manual' ]]; then
            juju add-machine ssh:ubuntu@$node
        fi
    done
    for node in $AGENT_NODES ; do
        if [[ $node != $NODE_IP && $CLOUD == 'manual' && ! " $CONTROLLER_NODES " =~ " $node " ]]; then
            juju add-machine ssh:ubuntu@$node
        fi
    done
fi
