#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname "$my_file")"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build machines k8s openstack tf wait logs" \
    ["default"]="machines k8s openstack tf wait" \
    ["master"]="build machines k8s openstack tf wait" \
    ["platform"]="machines k8s openstack" \
)

# default env variables
export DEPLOYER='ansible'
# max wait in seconds after deployment
export WAIT_TIMEOUT=300

tf_deployer_dir=${WORKSPACE}/tf-ansible-deployer
openstack_deployer_dir=${WORKSPACE}/tf-kolla-ansible
tf_deployer_image=${TF_ANSIBLE_DEPLOYER:-"tf-ansible-deployer-src"}
openstack_deployer_image=${OPENSTACK_DEPLOYER:-"tf-kolla-ansible-src"}

export ANSIBLE_CONFIG=$tf_deployer_dir/ansible.cfg

ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-rocky}
export AUTH_PASSWORD='contrail123'

export DOMAINSUFFIX=${DOMAINSUFFIX-$(hostname -d)}

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=( \
    ['AUTH_PASSWORD']="$AUTH_PASSWORD" \
)

function build() {
    "$my_dir/../common/dev_env.sh"
}

function logs() {
    local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
    set +e

    create_log_dir
    cp $tf_deployer_dir/instances.yaml ${TF_LOG_DIR}/
    collect_contrail_status
    collect_system_stats
    collect_docker_logs
    collect_contrail_logs

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    rm -rf $TF_LOG_DIR

    # Restore errexit state
    if [[ $errexit_state == 1 ]]; then
        set -e
    fi
}

# There are three fetch_deployer functions/methods now:
# - fetch_deployer_no_docker - the most advanced function - fetch deployer src container without installing docker. In the future it will replace all the others
# - fetch_deployer - function fetch deployer src container using docker. Needs docker to be installed on host
# - old_XXX_fetch_deployer - deprecated deployer method saved for backward compatibility. Will be removed in the future.

function old_ansible_fetch_deployer() {

    local deployer_image="contrail-kolla-ansible-deployer"
    sudo rm -rf "$tf_deployer_dir"
    sudo rm -rf "$openstack_deployer_dir"
    local image="$CONTAINER_REGISTRY/$deployer_image"
    [ -n "$CONTRAIL_CONTAINER_TAG" ] && image+=":$CONTRAIL_CONTAINER_TAG"
    sudo docker create --name $deployer_image --entrypoint /bin/true $image
    sudo docker cp $deployer_image:root - | tar -x -C $WORKSPACE
    sudo mv $WORKSPACE/root/contrail-ansible-deployer $tf_deployer_dir
    sudo mv $WORKSPACE/root/contrail-kolla-ansible $openstack_deployer_dir
    sudo docker rm -fv $deployer_image
    sudo rm -rf $WORKSPACE/root
}

function machines() {
    # install required packages

    echo "$DISTRO detected"
    if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
        # remove packages that may cause conflicts,
        # all requried ones be re-installed
        sudo yum autoremove -y python-yaml python-requests python-urllib3
        sudo yum install -y epel-release
        sudo yum install -y python-setuptools iproute jq bind-utils
    elif [ "$DISTRO" == "ubuntu" ]; then
        export DEBIAN_FRONTEND=noninteractive
        sudo -E apt-get update
        sudo -E apt-get install -y python-setuptools iproute2 python-crypto jq dnsutils
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

    if ! fetch_deployer_no_docker $tf_deployer_image $tf_deployer_dir ; then
        old_ansible_fetch_deployer
    elif [[ "$ORCHESTRATOR" == "openstack" ]] ; then
        fetch_deployer_no_docker $openstack_deployer_image $openstack_deployer_dir
    fi

    # generate inventory file

    export NODE_IP
    export CONTAINER_REGISTRY
    export CONTRAIL_CONTAINER_TAG
    export OPENSTACK_VERSION
    export USER=$(whoami)
    $my_dir/../common/jinja2_render.py < $my_dir/files/instances_$ORCHESTRATOR.yaml > $tf_deployer_dir/instances.yaml

    # create Ansible temporary dir under current user to avoid create it under root
    ansible -m "copy" --args="content=c dest='/tmp/rekjreekrbjrekj.txt'" localhost
    rm -rf /tmp/rekjreekrbjrekj.txt

    sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
        -e config_file=$tf_deployer_dir/instances.yaml \
        $tf_deployer_dir/playbooks/configure_instances.yml
    if [[ $? != 0 ]] ; then
        echo "Installation aborted. Instances preparation failed."
        exit 1
    fi
}

function k8s() {
    if [[ "$ORCHESTRATOR" != "kubernetes" ]]; then
        echo "INFO: Skipping k8s deployment"
    else
        sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
            -e config_file=$tf_deployer_dir/instances.yaml \
            $tf_deployer_dir/playbooks/install_k8s.yml

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
            -e config_file=$tf_deployer_dir/instances.yaml \
            $tf_deployer_dir/playbooks/install_openstack.yml
    fi
}

function tf() {
    sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
        -e config_file=$tf_deployer_dir/instances.yaml \
        $tf_deployer_dir/playbooks/install_contrail.yml
    echo "Contrail Web UI must be available at https://$NODE_IP:8143"
    [ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack UI must be avaiable at http://$NODE_IP"
    echo "Use admin/$AUTH_PASSWORD to log in"
}

# This is_active function is called in wait stage defined in common/stages.sh

function is_active() {
    if [[ "$ORCHESTRATOR" == "kubernetes" ]]; then
        check_pods_active
    fi

    check_tf_active
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}

run_stages $STAGE
