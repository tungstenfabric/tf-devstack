#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ~/rhosp-environment.sh
source "$my_dir/../providers/common/functions.sh"

sudo -E bash -c "CONTAINER_REGISTRY='' CONFIGURE_DOCKER_LIVERESTORE=false ${my_dir}/../../common/create_docker_config.sh"
insecure_registries=$(cat /etc/sysconfig/docker | awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' | tr -d '"')
echo "INFO: current insecure_registries=$insecure_registries"
if [[ -n "$CONTAINER_REGISTRY" ]] && is_registry_insecure "$CONTAINER_REGISTRY" ; then
    echo "INFO: add CONTAINER_REGISTRY=$CONTAINER_REGISTRY to insecure list"
    insecure_registries+=" --insecure-registry $CONTAINER_REGISTRY"
fi
if [[ -n "$OPENSTACK_CONTAINER_REGISTRY" ]] && is_registry_insecure "$OPENSTACK_CONTAINER_REGISTRY" ; then
    echo "INFO: add OPENSTACK_CONTAINER_REGISTRY=$OPENSTACK_CONTAINER_REGISTRY to insecure list"
    insecure_registries+=" --insecure-registry $OPENSTACK_CONTAINER_REGISTRY"
fi
sudo sed -i '/^INSECURE_REGISTRY/d' /etc/sysconfig/docker
echo "INSECURE_REGISTRY=\"$insecure_registries\""  | sudo tee -a /etc/sysconfig/docker
echo "INFO: restart docker, /etc/sysconfig/docker"
sudo cat /etc/sysconfig/docker
if ! sudo systemctl restart docker ; then
    echo "ERROR: sudo systemctl restart docker failed"
    sudo systemctl status docker.service
    sudo journalctl -xe
    exit 1
fi
