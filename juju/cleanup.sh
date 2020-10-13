#!/bin/bash -e
my_file="$(readlink -e "$0")"
my_dir="$(dirname ${my_file})"
source "${my_dir}/../common/common.sh"
source "${my_dir}/../common/functions.sh"

export CLOUD=${CLOUD:-manual}  # aws | maas | manual

rm -rf ~/.tf/.stages


echo "INFO: Removing all juju applications"

function get_app_names() {
    juju status --format json | jq '.applications' | jq -r 'keys[]'
}

function is_app_removed() {
    local app_name=$1
    get_app_names | grep -q "$app_name" && return 1 || return 0
}

function are_all_apps_removed() {
    [[ -z "$(get_app_names)" ]] && return 0 || return 1
}

# It's important to remove applications sequentially because this ensures that
# `stop` hooks work properly
for app_name in $(get_app_names)
do
    juju remove-application "$app_name"
    wait_cmd_success "is_app_removed $app_name" 1 60 || echo "WARNING: Application $app_name didn't removed"
done

if [[ -n "$(get_app_names)" ]]; then
    echo "INFO: Force removing applications"
    get_app_names | xargs -n 1 juju remove-application --force
    wait_cmd_success "are_all_apps_removed" || echo "WARNING: Some of applications weren't removed"
fi


echo "INFO: Destroy controller"
juju destroy-controller -y --destroy-all-models "tf-${CLOUD}-controller"

# On start controller juju changes configuration of fan, but after destroying it
# doesn't return everything to its place
echo "INFO: Destroy fan config"
sudo fanctl config list | while read -r addrs
do
    addrs=($addrs)
    fanatic disable-fan -u ${addrs[0]} -o ${addrs[1]}
done


if [[ -n "$(sudo docker ps -q)" ]]; then
    echo "WARNING: Some of docker containers weren't removed"
    sudo docker ps
    echo "INFO: Force removing docker containers"
    sudo docker stop $(sudo docker ps -aq)
    sudo docker rm $(sudo docker ps -aq)
fi


[[ $CLOUD == 'maas' ]] && echo "Cleanup is over." && exit # Why?


echo "INFO: Remove docker, lxc, juju."
set +e
    sudo apt-get purge -y lxd lxd-client
    sudo apt-get purge -y docker-ce=18.06.3~ce~3-0~ubuntu
    # sudo apt-get purge -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    # sudo apt-get purge -y jq dnsutils
    sudo apt -y autoremove
    sudo snap remove -y juju
set -e


echo "INFO: Remove other artifacts"
sudo rm -rf /var/lib/juju
sudo rm -rf /lib/systemd/system/juju*
sudo rm -rf /run/systemd/units/invocation:juju*
sudo rm -rf /etc/systemd/system/juju*
sudo rm -rf /etc/contrail/
sudo rm -rf /etc/docker

if [[ $CLOUD == 'manual' ]] && [[ -n "$CONTROLLER_NODES" || -n "$AGENT_NODES" ]]; then
    echo "INFO: Clean other nodes." 
    for machine in $CONTROLLER_NODES $AGENT_NODES ; do
        ssh ubuntu@$machine "sudo rm -rf /var/lib/juju ; sudo rm -rf /lib/systemd/system/juju* ; sudo rm -rf /run/systemd/units/invocation:juju* ; sudo rm -rf /etc/systemd/system/juju* ; sudo rm -rf /etc/contrail/ ; sudo rm -rf /etc/docker"
    done
fi

echo "INFO: Cleanup is over."




