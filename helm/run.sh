#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"
source "$my_dir/functions.sh"

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
export ORCHESTRATOR=${ORCHESTRATOR:-"kubernetes"}
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

function collect_logs() {
    cp $WORKSPACE/tf-devstack-values.yaml ${TF_LOG_DIR}/
    collect_logs_from_machines
}

run_stages $STAGE
