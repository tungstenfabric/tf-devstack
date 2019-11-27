#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname "$my_file")"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"

# stages declaration

declare -A STAGES=( \
    ["all"]="build machines k8s openstack tf wait" \
    ["default"]="machines k8s openstack tf wait" \
    ["master"]="build machines k8s openstack tf wait" \
    ["platform"]="k8s openstack" \
)

# default env variables

DEPLOYER_IMAGE="contrail-kolla-ansible-deployer"
DEPLOYER_DIR="root"
ANSIBLE_DEPLOYER_DIR="$WORKSPACE/$DEPLOYER_DIR/contrail-ansible-deployer"

ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-queens}

export DOMAINSUFFIX=${DOMAINSUFFIX-$(hostname -d)}

cd $WORKSPACE

function build() {
    "$my_dir/../common/dev_env.sh"
}

function machines() {
    # install required packages

    echo "$DISTRO detected"
    if [ "$DISTRO" == "centos" ]; then
        # remove packages that may cause conflicts,
        # all requried ones be re-installed
        sudo yum autoremove -y python-yaml python-requests python-urllib3
        sudo yum install -y python-setuptools iproute PyYAML
    elif [ "$DISTRO" == "ubuntu" ]; then
        sudo apt-get update
        sudo apt-get install -y python-setuptools iproute2 python-crypto
    else
        echo "Unsupported OS version"
        exit 1
    fi

    # setup timeserver
    setup_timeserver

    curl -s https://bootstrap.pypa.io/get-pip.py | sudo python
    # Uninstall docker-compose and packages it uses to avoid
    # conflicts with other projects (like tf-test, tf-dev-env)
    # and reinstall them via deps of docker-compose
    sudo pip uninstall -y requests docker-compose urllib3 chardet docker docker-py

    # docker-compose MUST be first here, because it will install the right version of PyYAML
    sudo pip install 'docker-compose==1.24.1' jinja2 'ansible==2.7.11'

    set_ssh_keys

    sudo -E "$my_dir/../common/install_docker.sh"

    fetch_deployer

    # generate inventory file

    export NODE_IP
    export CONTAINER_REGISTRY
    export CONTRAIL_CONTAINER_TAG
    export OPENSTACK_VERSION
    export USER=$(whoami)
    python "$my_dir/../common/jinja2_render.py" < $my_dir/files/instances_$ORCHESTRATOR.yaml > $ANSIBLE_DEPLOYER_DIR/instances.yaml

    ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
        -e config_file=$ANSIBLE_DEPLOYER_DIR/instances.yaml \
        $ANSIBLE_DEPLOYER_DIR/playbooks/configure_instances.yml
    if [[ $? != 0 ]]; then
        echo "Installation aborted. Instances preparation failed."
        exit 1
    fi
}

function k8s() {
    if [[ "$ORCHESTRATOR" != "kubernetes" ]]; then
        echo "INFO: Skipping k8s deployment"
    else
        ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
            -e config_file=$ANSIBLE_DEPLOYER_DIR/instances.yaml \
            $ANSIBLE_DEPLOYER_DIR/playbooks/install_k8s.yml
    fi
}

function openstack() {
    if [[ "$ORCHESTRATOR" != "openstack" ]]; then
        echo "INFO: Skipping openstack deployment"
    else
        ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
            -e config_file=$ANSIBLE_DEPLOYER_DIR/instances.yaml \
            $ANSIBLE_DEPLOYER_DIR/playbooks/install_openstack.yml
    fi
}

function tf() {
    ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
        -e config_file=$ANSIBLE_DEPLOYER_DIR/instances.yaml \
        $ANSIBLE_DEPLOYER_DIRplaybooks/install_contrail.yml
    echo "Contrail Web UI must be available at https://$NODE_IP:8143"
    [ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack UI must be avaiable at http://$NODE_IP"
    echo "Use admin/contrail123 to log in"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    [ "$ORCHESTRATOR" == "kubernetes" ] && check_pods_active && check_tf_active
}

run_stages $STAGE
