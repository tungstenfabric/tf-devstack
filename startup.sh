#!/bin/bash

[ "$(whoami)" != "root" ] && echo "Please run script as root user" && exit

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname "$my_file")"
source "$my_dir/common/common.sh"
source "$my_dir/common/functions.sh"

# default env variables

WORKSPACE="$(pwd)"
DEPLOYER_IMAGE="contrail-kolla-ansible-deployer"
DEPLOYER_DIR="root"

ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-queens}

# install required packages

echo "$DISTRO detected"
if [ "$DISTRO" == "centos" ]; then
    yum install -y python-setuptools iproute
    yum remove -y python-yaml
    yum remove -y python-requests
elif [ "$DISTRO" == "ubuntu" ]; then
    apt-get update
    apt-get install -y python-setuptools iproute2
else
    echo "Unsupported OS version"
    exit
fi

curl -s https://bootstrap.pypa.io/get-pip.py | python
pip install requests
pip install pyyaml==3.13
pip install 'ansible==2.7.11'

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
    # TODO: fix dev_env.sh and use it here
    #"$my_dir/../common/dev_env.sh"

    # get tf-dev-env
    [ -d /root/tf-dev-env ] && rm -rf /root/tf-dev-env
    cd /root && git clone https://github.com/tungstenfabric/tf-dev-env.git

    # build all
    cd /root/tf-dev-env && AUTOBUILD=1 BUILD_DEV_ENV=1 ./startup.sh

    # fix env variables
    CONTAINER_REGISTRY="$(docker inspect --format '{{(index .IPAM.Config 0).Gateway}}' bridge):6666"
    CONTRAIL_CONTAINER_TAG="dev"
else
    "$my_dir/common/install_docker.sh"
fi

fetch_deployer

# generate inventory file

ansible_deployer_dir="$WORKSPACE/$DEPLOYER_DIR/contrail-ansible-deployer"
export NODE_IP
export CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG
export OPENSTACK_VERSION
envsubst < $my_dir/instance_$ORCHESTRATOR.yaml > $ansible_deployer_dir/instance.yaml

cd $ansible_deployer_dir
# step 1 - configure instances

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$ansible_deployer_dir/instance.yaml \
    playbooks/configure_instances.yml
if [[ $? != 0 ]]; then
    echo "Installation aborted"
    exit
fi

# step 2 - install orchestrator

playbook_name="install_k8s.yml"
[ "$ORCHESTRATOR" == "openstack" ] && playbook_name="install_openstack.yml"

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$ansible_deployer_dir/instance.yaml \
    playbooks/$playbook_name
if [[ $? != 0 ]]; then
    echo "Installation aborted"
    exit
fi

# step 3 - install Tungsten Fabric

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$ansible_deployer_dir/instance.yaml \
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
