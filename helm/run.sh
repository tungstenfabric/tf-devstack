#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

# stages declaration

declare -A STAGES=( \
    ["all"]="build k8s openstack tf wait logs" \
    ["default"]="k8s openstack tf wait" \
    ["master"]="build k8s openstack tf wait" \
    ["platform"]="k8s openstack" \
)

# default env variables

DEPLOYER_IMAGE="contrail-helm-deployer"
DEPLOYER_DIR="root"

CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}
ORCHESTRATOR=${ORCHESTRATOR:-"openstack"}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-queens}

if [[ "$ORCHESTRATOR" == "openstack" ]]; then
  export CNI=${CNI:-calico}
elif [[ "$ORCHESTRATOR" != "kubernetes" ]]; then
  echo "Set ORCHESTRATOR environment variable with value \"kubernetes\" or \"openstack\"  "
  exit 1
fi

function build() {
    "$my_dir/../common/dev_env.sh"
}

function logs() {
    collect_docker_logs

    local cdir=`pwd`
    cd $WORKSPACE
    tar -czf logs.tgz logs
    rm -rf logs
    cd $cdir
}

function k8s() {
    export K8S_NODES=$AGENT_NODES
    export K8S_MASTERS=$CONTROLLER_NODES
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

run_stages $STAGE
