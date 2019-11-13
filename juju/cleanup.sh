#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

export CLOUD=${CLOUD:-local}  # aws | local | manual

CONTROLLER_NODES=${CONTROLLER_NODES:-}

echo "Destroying tf-$CLOUD-controller controller, machines, applications and data."
juju kill-controller -y tf-$CLOUD-controller

echo "Clean up the juju-controller-node."
sudo rm -rf /var/lib/juju
sudo rm -rf /lib/systemd/system/juju*
sudo rm -rf /run/systemd/units/invocation:juju*
sudo rm -rf /etc/systemd/system/juju*

if [[ $CLOUD == 'manual' && -n "$CONTROLLER_NODES" ]]; then
    echo "Clean other nodes." 
    for machine in `echo $CONTROLLER_NODES | tr ',' ' '` ; do
        ssh ubuntu@$machine "sudo rm -rf /var/lib/juju ; sudo rm -rf /lib/systemd/system/juju* ; sudo rm -rf /run/systemd/units/invocation:juju* ; sudo rm -rf /etc/systemd/system/juju*"
    done
fi

echo "Cleanup is over."
