#!/bin/bash -x

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
# 300 is small sometimes - NTP sync can be an issue
export WAIT_TIMEOUT=600

tf_deployer_dir=${WORKSPACE}/tf-ansible-deployer
openstack_deployer_dir=${WORKSPACE}/contrail-kolla-ansible
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

    cat <<EOF >/tmp/logs.sh
#!/bin/bash
tgz_name=\$1
export WORKSPACE=/tmp/ansible-logs
export TF_LOG_DIR=/tmp/ansible-logs/logs
export SSL_ENABLE=$SSL_ENABLE
cd /tmp/ansible-logs
source ./collect_logs.sh
collect_contrail_status
collect_system_stats
collect_docker_logs
collect_contrail_logs
if [[ "$ORCHESTRATOR" == "openstack" ]]; then
    collect_kolla_logs
else
    collect_kubernetes_logs
    collect_kubernetes_objects_info
fi
chmod -R a+r logs
pushd logs
tar -czf \$tgz_name *
popd
cp logs/\$tgz_name \$tgz_name
rm -rf logs
EOF
    chmod a+x /tmp/logs.sh

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local machine
    for machine in $(echo "$CONTROLLER_NODES $AGENT_NODES" | tr " " "\n" | sort -u) ; do
        local tgz_name="logs-$machine.tgz"
        mkdir -p $TF_LOG_DIR/$machine
        ssh $ssh_opts $machine "mkdir -p /tmp/ansible-logs"
        scp $ssh_opts $my_dir/../common/collect_logs.sh $machine:/tmp/ansible-logs/collect_logs.sh
        scp $ssh_opts /tmp/logs.sh $machine:/tmp/ansible-logs/logs.sh
        ssh $ssh_opts $machine /tmp/ansible-logs/logs.sh $tgz_name
        scp $ssh_opts $machine:/tmp/ansible-logs/$tgz_name $TF_LOG_DIR/$machine/
        pushd $TF_LOG_DIR/$machine/
        tar -xzf $tgz_name
        rm -rf $tgz_name
        popd
    done

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    sudo rm -rf $TF_LOG_DIR

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
        sudo yum install -y python3 python3-setuptools libselinux-python3 libselinux-python iproute jq bind-utils
    elif [ "$DISTRO" == "ubuntu" ]; then
        export DEBIAN_FRONTEND=noninteractive
        sudo -E apt-get update
        sudo -E apt-get install -y python-setuptools python3-distutils iproute2 python-crypto jq dnsutils
    else
        echo "Unsupported OS version"
        exit 1
    fi

    # setup timeserver
    setup_timeserver

    # pip3 is installed at /usr/local/bin which is not in sudoers secure_path by default
    # use it as "python3 -m pip" with sudo
    curl --retry 3 --retry-delay 10 https://bootstrap.pypa.io/get-pip.py | sudo python3
    curl --retry 3 --retry-delay 10 https://bootstrap.pypa.io/get-pip.py | sudo python2 - 'pip==20.1'

    # Uninstall docker-compose and packages it uses to avoid
    # conflicts with other projects (like tf-dev-test, tf-dev-env)
    # and reinstall them via deps of docker-compose
    sudo python2 -m pip uninstall -y requests docker-compose urllib3 chardet docker docker-py

    # docker-compose MUST be first here, because it will install the right version of PyYAML
    sudo python2 -m pip install 'docker-compose==1.24.1' 'ansible==2.7.11'
    # jinja is reqiured to create some configs
    sudo python3 -m pip install jinja2

    set_ssh_keys

    if ! fetch_deployer_no_docker $tf_deployer_image $tf_deployer_dir ; then
        "$my_dir/../common/install_docker.sh"
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
    python3 $my_dir/../common/jinja2_render.py < $my_dir/files/instances.yaml.j2 > $tf_deployer_dir/instances.yaml

    # create Ansible temporary dir under current user to avoid create it under root
    ansible -m "copy" --args="content=c dest='/tmp/rekjreekrbjrekj.txt'" localhost
    rm -rf /tmp/rekjreekrbjrekj.txt

    export CONTRAIL_CONTAINER_TAG_PLATFORM=${CONTRAIL_CONTAINER_TAG:-}
    export CONTAINER_REGISTRY_PLATFORM=${CONTAINER_REGISTRY:-}

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
    if [[ "$CONTRAIL_CONTAINER_TAG_PLATFORM" != "$CONTRAIL_CONTAINER_TAG" || \
    "$CONTAINER_REGISTRY_PLATFORM" != "$CONTAINER_REGISTRY" ]]; then
        # generate new inventory file
        export NODE_IP
        export CONTAINER_REGISTRY
        export CONTRAIL_CONTAINER_TAG
        export OPENSTACK_VERSION
        export USER=$(whoami)
        python3 $my_dir/../common/jinja2_render.py < $my_dir/files/instances.yaml.j2 > $tf_deployer_dir/instances.yaml

        sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
        -e config_file=$tf_deployer_dir/instances.yaml \
        $tf_deployer_dir/playbooks/configure_instances.yml

        if [[ "$ORCHESTRATOR" == "openstack" ]]; then
            sudo -E ansible-playbook -v -e orchestrator=$ORCHESTRATOR \
                -e config_file=$tf_deployer_dir/instances.yaml \
                $tf_deployer_dir/playbooks/install_openstack.yml \
                --tags "nova,neutron,heat,ironic-notification-manager"
        fi
    fi

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
    if [[ $ORCHESTRATOR == 'openstack' || "$ORCHESTRATOR" == "all" ]] ; then
        DEPLOYMENT_ENV['OPENSTACK_CONTROLLER_NODES']="$(echo $CONTROLLER_NODES | cut -d ' ' -f 1)"
    fi
}

run_stages $STAGE
