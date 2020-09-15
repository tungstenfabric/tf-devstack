#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build k8s openstack tf wait logs" \
    ["default"]="k8s openstack tf wait" \
    ["master"]="build k8s openstack tf wait" \
    ["platform"]="k8s openstack" \
)

# default env variables
export DEPLOYER='helm'
# max wait in seconds after deployment (helm_os=600)
export WAIT_TIMEOUT=1200
DEPLOYER_IMAGE="contrail-helm-deployer"
DEPLOYER_DIR="root"

CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}
ORCHESTRATOR=${ORCHESTRATOR:-"kubernetes"}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-rocky}
# password is hardcoded in keystone/values.yaml (can be overriden) and in setup-clients.sh (can be hacked)
export AUTH_PASSWORD="password"

if [[ "$ORCHESTRATOR" == "openstack" ]]; then
  export CNI=${CNI:-calico}
elif [[ "$ORCHESTRATOR" != "kubernetes" ]]; then
  echo "Set ORCHESTRATOR environment variable with value \"kubernetes\" or \"openstack\"  "
  exit 1
fi

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=( \
    ['AUTH_URL']="http://keystone.openstack.svc.cluster.local:80/v3" \
    ['AUTH_PASSWORD']="$AUTH_PASSWORD" \
)

function build() {
    "$my_dir/../common/dev_env.sh"
}

function logs() {
    local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
    set +e
    create_log_dir
    cp $WORKSPACE/tf-devstack-values.yaml ${TF_LOG_DIR}/

    cat <<EOF >/tmp/logs.sh
#!/bin/bash
tgz_name=\$1
export WORKSPACE=/tmp/helm-logs
export TF_LOG_DIR=/tmp/helm-logs/logs
export SSL_ENABLE=$SSL_ENABLE
DISTRO=\$(cat /etc/*release | egrep '^ID=' | awk -F= '{print \$2}' | tr -d \")
if [ "\$DISTRO" == "centos" ]; then
    sudo yum install -y lsof jq
elif [ "\$DISTRO" == "ubuntu" ]; then
    export DEBIAN_FRONTEND=noninteractive
    sudo -E apt-get install -y lsof jq
fi
cd /tmp/helm-logs
source ./collect_logs.sh
collect_docker_logs
collect_contrail_status
collect_system_stats
collect_kubernetes_logs
collect_kubernetes_objects_info
collect_contrail_logs
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
        ssh $ssh_opts $machine "mkdir -p /tmp/helm-logs"
        scp $ssh_opts $my_dir/../common/collect_logs.sh $machine:/tmp/helm-logs/collect_logs.sh
        scp $ssh_opts /tmp/logs.sh $machine:/tmp/helm-logs/logs.sh
        ssh $ssh_opts $machine /tmp/helm-logs/logs.sh $tgz_name
        scp $ssh_opts $machine:/tmp/helm-logs/$tgz_name $TF_LOG_DIR/$machine/
        pushd $TF_LOG_DIR/$machine/
        tar -xzf $tgz_name
        rm -rf $tgz_name
        popd
    done

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    rm -rf $TF_LOG_DIR

    # Restore errexit state
    if [[ $errexit_state == 1 ]]; then
        set -e
    fi
}

function k8s() {
    export K8S_NODES="$AGENT_NODES"
    export K8S_MASTERS="$CONTROLLER_NODES"
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
    $my_dir/../common/deploy_kubespray.sh
}

function openstack() {
    if [[ $ORCHESTRATOR != "openstack" ]]; then
        echo "INFO: Skipping openstack deployment"
    else
        $my_dir/deploy_helm_openstack.sh
    fi
}

function tf() {
    $my_dir/deploy_tf_helm.sh
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
     check_pods_active && check_tf_active
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}

run_stages $STAGE
