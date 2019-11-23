#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname "$my_file")"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

cd $WORKSPACE

# default env variables

DEPLOYER_IMAGE="contrail-kolla-ansible-deployer"
DEPLOYER_DIR="root"

ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-queens}

export DOMAINSUFFIX=${DOMAINSUFFIX-$(hostname -d)}

# install required packages

echo "$DISTRO detected"
if [ "$DISTRO" == "centos" ]; then
  # remove packages taht may cause conflicts, 
  # all requried ones be re-installed
  sudo yum autoremove -y python-yaml python-requests python-urllib3
  sudo yum install -y python-setuptools iproute PyYAML
elif [ "$DISTRO" == "ubuntu" ]; then
  sudo apt-get update
  sudo apt-get install -y python-setuptools iproute2 python-crypto
else
  echo "Unsupported OS version"
  exit
fi

# install pip
curl -s https://bootstrap.pypa.io/get-pip.py | sudo python
# Uninstall docker-compose and packages it uses to avoid 
# conflicts with other projects (like tf-test, tf-dev-env)
# and reinstall them via deps of docker-compose
sudo pip uninstall -y requests docker-compose urllib3 chardet docker docker-py

# docker-compose MUST be first here, because it will install the right version of PyYAML
sudo pip install 'docker-compose==1.24.1' jinja2 'ansible==2.7.11'

# show config variables

[ "$NODE_IP" != "" ] && echo "Node IP: $NODE_IP"
echo "Build from source: $DEV_ENV" # true or false
echo "Orchestrator: $ORCHESTRATOR" # kubernetes or openstack
[ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack version: $OPENSTACK_VERSION"
echo

# prepare ssh key authorization

[ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
[ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
[ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

sudo -E "$my_dir/../common/install_docker.sh"

# build step

if [[ "$DEV_ENV" == true ]] ; then
  "$my_dir/../common/dev_env.sh"
fi
load_tf_devenv_profile

fetch_deployer

# generate inventory file

ansible_deployer_dir="$WORKSPACE/$DEPLOYER_DIR/contrail-ansible-deployer"
export NODE_IP
export CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG
export OPENSTACK_VERSION
export USER=$(whoami)
python "$my_dir/../common/jinja2_render.py" < $my_dir/instances_$ORCHESTRATOR.yaml > $ansible_deployer_dir/instances.yaml

cd $ansible_deployer_dir
# step 1 - configure instances

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$ansible_deployer_dir/instances.yaml \
    playbooks/configure_instances.yml
if [[ $? != 0 ]]; then
  echo "Installation aborted. Instances preparation failed."
  exit
fi

# step 2 - install orchestrator

playbook_name="install_k8s.yml"
[ "$ORCHESTRATOR" == "openstack" ] && playbook_name="install_openstack.yml"

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$ansible_deployer_dir/instances.yaml \
    playbooks/$playbook_name
if [[ $? != 0 ]]; then
  echo "Installation aborted. Failed to run $playbook_name"
  exit
fi

# step 3 - install Tungsten Fabric

ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
    -e config_file=$ansible_deployer_dir/instances.yaml \
    playbooks/install_contrail.yml
if [[ $? != 0 ]]; then
  echo "Installation aborted. Contrail installation has been failed."
  exit
fi

# safe tf stack profile

save_tf_stack_profile

# show results

echo
echo "Deployment scripts are finished"
[ "$DEV_ENV" == "true" ] && echo "Please reboot node before testing"
echo "Contrail Web UI must be available at https://$NODE_IP:8143"
[ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack UI must be avaiable at http://$NODE_IP"
echo "Use admin/contrail123 to log in"
