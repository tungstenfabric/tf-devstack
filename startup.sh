#!/bin/bash

set -o errexit

# checks
supported_distros=(centos ubuntu)
distro=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
echo $distro detected.
if [[ ! " ${supported_distros[@]} " =~ " ${distro} " ]]; then
  echo "Unsupported OS version: ${distro}" && exit
fi
[ "$(whoami)" != "root" ] && echo Please run script as root user && exit

TF_DEVSTACK_DIR=$(dirname "$(readlink /proc/$$/fd/255)")

source $TF_DEVSTACK_DIR/common.sh

# default env variables

ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}

if [ "$ORCHESTRATOR" == "kubernetes" ]; then
  CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-master-latest}
  set_default_k8s_version
  K8S_VERSION=${K8S_VERSION:-$default_k8s_version}
  DOCKER_VERSION=${DOCKER_VERSION:-"18.06.0"}
elif [ "$ORCHESTRATOR" == "openstack" ]; then
  CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-ocata-master-latest}
  OPENSTACK_VERSION=${OPENSTACK_VERSION:-ocata}
  DOCKER_VERSION=${DOCKER_VERSION:-"18.03.1"}
else
  echo "Unsupported orchestrator: ${ORCHESTRATOR}" && exit
fi

DEV_ENV=${DEV_ENV:-false}

REGISTRY_PORT=${REGISTRY_PORT:-5000}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-opencontrailnightly}

install_required_packages

PHYSICAL_INTERFACE=$(ip route get 1 | grep -o 'dev.*' | awk '{print($2)}')
NODE_IP=$(ip addr show dev $PHYSICAL_INTERFACE | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1)

# show config variables

[ "$NODE_IP" != "" ] && echo "Node IP: $NODE_IP"
echo "Build from source: $DEV_ENV" # true or false
echo "Orchestrator: $ORCHESTRATOR" # kubernetes or openstack
[ "$ORCHESTRATOR" == "kubernetes" ] && [ "$K8S_VERSION" != "" ] && echo "Kubernetes version: $K8S_VERSION"
[ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack version: $OPENSTACK_VERSION"
echo "Contrail container tag: $CONTRAIL_CONTAINER_TAG"
echo "Docker version: $DOCKER_VERSION"
echo

# prepare ssh key authorization
prepare_ssh_key_authorization

# build step

install_docker

echo 
export NODE_IP
export CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG
export K8S_VERSION
export OPENSTACK_VERSION
export DEV_ENV
export REGISTRY_PORT

if [ "$DEV_ENV" == "true" ]; then
	build_docker_images
fi

get_ansible_deployer

# generate inventory file

envsubst < $TF_DEVSTACK_DIR/instance_$ORCHESTRATOR.yaml > $TF_DEVSTACK_DIR/instance.yaml
# step 1 - configure instances

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$TF_DEVSTACK_DIR/instance.yaml \
    playbooks/configure_instances.yml

[ $? -gt 1 ] && echo Installation aborted && exit

# step 2 - install orchestrator

playbook_name="install_k8s.yml"
[ "$ORCHESTRATOR" == "openstack" ] && playbook_name="install_openstack.yml"

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$TF_DEVSTACK_DIR/instance.yaml \
    playbooks/$playbook_name

[ $? -gt 1 ] && echo Installation aborted && exit

# step 3 - install Tungsten Fabric

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$TF_DEVSTACK_DIR/instance.yaml \
    playbooks/install_contrail.yml

[ $? -gt 1 ] && echo Installation aborted && exit

# show results

echo
echo Deployment scripts are finished
[ "$DEV_ENV" == "true" ] && echo Please reboot node before testing
echo Contrail Web UI must be available at https://$NODE_IP:8143
[ "$ORCHESTRATOR" == "openstack" ] && echo OpenStack UI must be avaiable at http://$NODE_IP
echo Use admin/contrail123 to log in
