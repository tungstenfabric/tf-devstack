#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

export CLOUD=${CLOUD:-local}  # aws | local | manual

rm -rf ~/.tf/.stages

echo "Destroying tf-$CLOUD-controller controller, machines, applications and data."
if [ -n "$(juju status --format json | jq '.applications' | jq -r 'keys[]')" ]; then
    juju status --format json | jq '.applications' | jq -r 'keys[]' | xargs -n 1 juju remove-application --force
fi

function no_apps_left() {
    if [ -z "$(juju status --format json | jq '.applications' | jq -r 'keys[]')" ]; then
        return 0
    fi
    return 1
}

wait_cmd_success "no_apps_left"

juju destroy-controller -y --destroy-all-models tf-$CLOUD-controller

[[ $CLOUD == 'maas' ]] && echo "Cleanup is over." && exit

echo "Clean up the juju-controller-node."
sudo rm -rf /var/lib/juju
sudo rm -rf /lib/systemd/system/juju*
sudo rm -rf /run/systemd/units/invocation:juju*
sudo rm -rf /etc/systemd/system/juju*
sudo rm -rf /etc/contrail/
sudo rm -rf /etc/docker

if [[ $CLOUD == 'manual' ]] && [[ -n "$CONTROLLER_NODES" || -n "$AGENT_NODES" ]]; then
    echo "Clean other nodes." 
    for machine in $CONTROLLER_NODES $AGENT_NODES ; do
        ssh ubuntu@$machine "sudo rm -rf /var/lib/juju ; sudo rm -rf /lib/systemd/system/juju* ; sudo rm -rf /run/systemd/units/invocation:juju* ; sudo rm -rf /etc/systemd/system/juju* ; sudo rm -rf /etc/contrail/ ; sudo rm -rf /etc/docker"
    done
fi

echo "Cleanup is over."
