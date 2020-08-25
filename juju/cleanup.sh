#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

export CLOUD=${CLOUD:-manual}  # aws | maas | manual

rm -rf ~/.tf/.stages

echo "Destroying tf-$CLOUD-controller controller, machines, applications and data."
juju kill-controller -y tf-$CLOUD-controller || juju unregister -y tf-$CLOUD-controller

[[ $CLOUD == 'maas' ]] && echo "Cleanup is over." && exit

echo "Clean up the juju-controller-node."
sudo rm -rf /var/lib/juju
sudo rm -rf /lib/systemd/system/juju*
sudo rm -rf /run/systemd/units/invocation:juju*
sudo rm -rf /etc/systemd/system/juju*

if [[ $CLOUD == 'manual' ]] && [[ -n "$CONTROLLER_NODES" || -n "$AGENT_NODES" ]]; then
    echo "Clean other nodes." 
    for machine in $CONTROLLER_NODES $AGENT_NODES ; do
        ssh ubuntu@$machine "sudo rm -rf /var/lib/juju ; sudo rm -rf /lib/systemd/system/juju* ; sudo rm -rf /run/systemd/units/invocation:juju* ; sudo rm -rf /etc/systemd/system/juju*"
    done
fi

echo "Cleanup is over."
