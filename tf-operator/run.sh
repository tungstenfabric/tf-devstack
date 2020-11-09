#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"
# stages declaration

declare -A STAGES=( \
    ["default"]="k8s tf wait" \
    ["platform"]="k8s" \
)

# constants
export DEPLOYER='operator'
# max wait in seconds after deployment
export WAIT_TIMEOUT=1200
deployer_image=tf-operator
deployer_dir=${WORKSPACE}/tf-container-builder
AGENT_LABEL="node-role.opencontrail.org/agent="

# default env variables
CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

# stages
function k8s() {
    export K8S_NODES="$AGENT_NODES"
    export K8S_MASTERS="$CONTROLLER_NODES"
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
    $my_dir/../common/deploy_kubespray.sh
}

function tf() {
    git clone https://github.com/progmaticlab/tf-operator.git $WORKSPACE/tf-operator

    # build operator and CRDS containers
    $WORKSPACE/tf-operator/scripts/setup_build_sofware.sh
    python3 -m venv $WORKSPACE/python3-env
    source $WORKSPACE/python3-env/bin/activate
    $WORKSPACE/tf-operator/scripts/build_containers_bazel.sh

    # Run operator
    ensure_kube_api_ready
    kubectl apply -k $WORKSPACE/tf-operator/deploy/kustomize/operator/latest
    while [ ! $(kubectl wait crds --for=condition=Established --timeout=2m managers.contrail.juniper.net) ]
    do
        sleep 2s
    done
    kubectl apply -k $WORKSPACE/tf-operator/deploy/kustomize/contrail/1node/latest
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    check_pods_active && check_tf_active
}

run_stages $STAGE
