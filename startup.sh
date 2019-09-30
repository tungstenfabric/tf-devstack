#!/bin/bash

set -o errexit

# default env variables

ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}
DEV_ENV=${DEV_ENV:-false}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-queens}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-opencontrailnightly}
CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-ocata-master-latest}

[ "$(whoami)" != "root" ] && echo "Please run script as root user" && exit

distro=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
echo "$distro detected"

# install required packages

if [ "$distro" == "centos" ]; then
    yum install -y python-setuptools  iproute
    yum remove -y python-yaml
    yum remove -y python-requests
elif [ "$distro" == "ubuntu" ]; then
    apt-get update
    apt-get install -y python-setuptools iproute
else
    echo "Unsupported OS version"
    exit
fi

easy_install pip
pip install requests
pip install pyyaml==3.13
pip install 'ansible==2.7.11'

PHYSICAL_INTERFACE=`ip route get 1 | grep -o 'dev.*' | awk '{print($2)}'`
NODE_IP=`ip addr show dev $PHYSICAL_INTERFACE | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1`

# show config variables

[ "$NODE_IP" != "" ] && echo "Node IP: $NODE_IP"
echo "Build from source: $DEV_ENV" # true or false
echo "Orchestrator: $ORCHESTRATOR" # kubernetes or openstack
[ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack version: $OPENSTACK_VERSION"
echo

# prepare ssh key authorization

[ ! -d /root/.ssh ] && mkdir /root/.ssh && chmod 0700 /root/.ssh
[ ! -f /root/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N ''
[ ! -f /root/.ssh/authorized_keys ] && touch /root/.ssh/authorized_keys && chmod 0600 /root/.ssh/authorized_keys
grep "$(</root/.ssh/id_rsa.pub)" /root/.ssh/authorized_keys -q || cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

# build step

if [ "$DEV_ENV" == "true" ]; then
    # get tf-dev-env
    [ -d /root/tf-dev-env ] && rm -rf /root/tf-dev-env
    cd /root && git clone https://github.com/tungstenfabric/tf-dev-env.git

    # build all
    cd /root/tf-dev-env && AUTOBUILD=1 BUILD_DEV_ENV=1 ./startup.sh

    # fix env variables
    CONTAINER_REGISTRY="$(docker inspect --format '{{(index .IPAM.Config 0).Gateway}}' bridge):6666"
    CONTRAIL_CONTAINER_TAG="dev"
fi

# get contrail-ansible-deployer from git

[ -d /root/contrail-ansible-deployer ] && rm -rf /root/contrail-ansible-deployer
cd /root && git clone https://github.com/Juniper/contrail-ansible-deployer.git
cd /root/contrail-ansible-deployer

# generate inventory file

export NODE_IP
export CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG
export OPENSTACK_VERSION
envsubst < /root/tf-devstack/instance_$ORCHESTRATOR.yaml > /root/tf-devstack/instance.yaml

# step 1 - configure instances

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=/root/tf-devstack/instance.yaml \
    playbooks/configure_instances.yml
if [[ $? != 0 ]]; then
    echo "Installation aborted"
    exit
fi

# step 2 - install orchestrator

playbook_name="install_k8s.yml"
[ "$ORCHESTRATOR" == "openstack" ] && playbook_name="install_openstack.yml"

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=/root/tf-devstack/instance.yaml \
    playbooks/$playbook_name
if [[ $? != 0 ]]; then
    echo "Installation aborted"
    exit
fi

# step 3 - install Tungsten Fabric

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=/root/tf-devstack/instance.yaml \
    playbooks/install_contrail.yml
if [[ $? != 0 ]]; then
    echo "Installation aborted"
    exit
fi

# show results

echo
echo "Deployment scripts are finished"
[ "$DEV_ENV" == "true" ] && echo "Please reboot node before testing"
echo "Contrail Web UI must be available at https://$NODE_IP:8143"
[ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack UI must be avaiable at http://$NODE_IP"
echo "Use admin/contrail123 to log in"
