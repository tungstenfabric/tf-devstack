#!/bin/bash

function is_registry_insecure() {
    local registry=`echo $1 | sed 's|^.*://||' | cut -d '/' -f 1`
    if  curl -s -I --connect-timeout 60 http://$registry/v2/ ; then
        return 0
    fi
    return 1
}

function patch_docker_configs(){
    # No needs to have container registry on undercloud.
    # For now overcloud nodes download them directly from $CONTAINER_REGISTRY
    sudo -E CONTAINER_REGISTRY="" CONFIGURE_DOCKER_LIVERESTORE=false $my_dir/../common/create_docker_config.sh || return 1
    local insecure_registries=$(sudo awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' /etc/sysconfig/docker | tr -d '"')
    if [ -n "$CONTAINER_REGISTRY" ] && is_registry_insecure $CONTAINER_REGISTRY ; then
       insecure_registries+=" --insecure-registry $CONTAINER_REGISTRY"
    fi
    sudo sed -i '/^INSECURE_REGISTRY/d' /etc/sysconfig/docker
    echo "INSECURE_REGISTRY=\"$insecure_registries\""  | sudo tee -a /etc/sysconfig/docker
    if ! sudo systemctl restart docker ; then
        sudo systemctl status docker.service
        sudo journalctl -xe
        return 1
    fi
} 