#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname "$my_file")"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

# stages declaration

declare -A STAGES=( \
    ["all"]="build machines k8s openstack tf wait logs" \
    ["default"]="machines k8s openstack tf wait" \
    ["master"]="build machines k8s openstack tf wait" \
    ["platform"]="machines k8s openstack" \
)

# default env variables

DEPLOYER_IMAGE="contrail-kolla-ansible-deployer"
DEPLOYER_DIR="root"
ANSIBLE_DEPLOYER_DIR="$WORKSPACE/$DEPLOYER_DIR/contrail-ansible-deployer"
export ANSIBLE_CONFIG=$ANSIBLE_DEPLOYER_DIR/ansible.cfg

ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-queens}

export DOMAINSUFFIX=${DOMAINSUFFIX-$(hostname -d)}

cd $WORKSPACE

function build() {
    "$my_dir/../common/dev_env.sh"
}

function logs() {
    collect_docker_logs

    tar -czf $WORKSPACE/logs.tgz $WORKSPACE/logs
    rm -rf $WORKSPACE/logs
}

function machines() {
    # install required packages

    echo "$DISTRO detected"
    if [ "$DISTRO" == "centos" ]; then
        # remove packages that may cause conflicts,
        # all requried ones be re-installed
        sudo yum autoremove -y python-yaml python-requests python-urllib3
        sudo yum install -y python-setuptools iproute
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

    "$my_dir/../common/install_docker.sh"

    fetch_deployer

    # generate inventory file

    export NODE_IP
    export CONTAINER_REGISTRY
    export CONTRAIL_CONTAINER_TAG
    export OPENSTACK_VERSION
    export USER=$(whoami)
    python "$my_dir/../common/jinja2_render.py" < $my_dir/files/instances_$ORCHESTRATOR.yaml > $ANSIBLE_DEPLOYER_DIR/instances.yaml

    # create Ansible temporary dir under current user to avoid create it under root
    ansible -m "copy" --args="content=c dest='/tmp/rekjreekrbjrekj.txt'" localhost
    rm -rf /tmp/rekjreekrbjrekj.txt

    sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
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
        sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
            -e config_file=$ANSIBLE_DEPLOYER_DIR/instances.yaml \
            $ANSIBLE_DEPLOYER_DIR/playbooks/install_k8s.yml

        # To use kubectl current user must have Kubernetes config
        if [[ ! -d ~/.kube ]]; then
          mkdir ~/.kube
        fi

        if [[ ! -f ~/.kube/config ]]; then
          sudo cp /root/.kube/config ~/.kube/
          sudo chown $USER ~/.kube/config
        fi
    fi
}

function openstack() {
    if [[ "$ORCHESTRATOR" != "openstack" ]]; then
        echo "INFO: Skipping openstack deployment"
    else
        sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
            -e config_file=$ANSIBLE_DEPLOYER_DIR/instances.yaml \
            $ANSIBLE_DEPLOYER_DIR/playbooks/install_openstack.yml
    fi
}

function tf() {
    sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
        -e config_file=$ANSIBLE_DEPLOYER_DIR/instances.yaml \
        $ANSIBLE_DEPLOYER_DIR/playbooks/install_contrail.yml
    echo "Contrail Web UI must be available at https://$NODE_IP:8143"
    [ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack UI must be avaiable at http://$NODE_IP"
    echo "Use admin/contrail123 to log in"
}

# This is_active function is called in wait stage defined in common/stages.sh

function is_active() {
    if [[ "$ORCHESTRATOR" == "kubernetes" ]]; then
        check_pods_active
    fi

    check_tf_active
}

run_stages $STAGE
