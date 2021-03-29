#!/bin/bash

# Adds CONTROLLER_NODES and AGENT_NODES to model for manual deployment

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"

for node in $CONTROLLER_NODES ; do
    if [[ $node != $NODE_IP && $CLOUD == 'manual' ]]; then
        echo "INFO: add machine $SSH_USER@$node for controller"
        juju add-machine ssh:$SSH_USER@$node
    fi
done

for node in $AGENT_NODES ; do
    if [[ $node != $NODE_IP && $CLOUD == 'manual' && ! " $CONTROLLER_NODES " =~ " $node " ]]; then
        echo "INFO: add machine $SSH_USER@$node for agent"
        juju add-machine ssh:$SSH_USER@$node
    fi
done

# zfs in a same disk doesn't help
# TODO: check timings with zfs on separate disk
#echo "INFO: init LXD with ZFS"
#for machine in $(timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $3}') ; do
#    echo "INFO: checking LXD state on machine $machine"
#    if ! juju ssh $machine lxc storage list | grep default ; then
#        echo "INFO: try to init LXD storage with ZFS on machine $machine"
#        ssh $SSH_USER@$machine sudo apt-get install -y zfsutils-linux
#        ssh $SSH_USER@$machine "lxd init --auto --storage-backend=zfs --storage-create-loop=40 ; lxc network set lxdbr0 ipv6.address none"
#    fi
#done

echo "INFO: juju machines added"
