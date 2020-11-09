#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"
# stages declaration

declare -A STAGES=( \
    ["default"]="k8s fetch build tf wait" \
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

function fetch_deployer {
    git clone https://github.com/progmaticlab/tf-operator.git $WORKSPACE
}

# setup build software and build contrail-operator container into local registry
function build() {
    scripts/setup_build_sofware.sh
    python3 -m venv $WORKSPACE/python3-env
    source $WORKSPACE/python3-env/bin/activate
    scripts/build_containers_bazel.sh
}

function tf() {
    ensure_kube_api_ready

    # label nodes
    labels=( $(grep "key: \"node-role." $WORKSPACE/contrail.yaml | tr -s [:space:] | sort -u | cut -d: -f2 | tr -d \") )
    label_nodes_by_ip $AGENT_LABEL $AGENT_NODES
    for label in ${labels[@]}
    do
        label_nodes_by_ip "$label=" $CONTROLLER_NODES
    done

    kubectl apply -f $WORKSPACE/contrail-operator/deploy/create-operator.yaml
    kubectl wait crds --for=condition=Established --timeout=2m managers.contrail.juniper.net
    kubectl apply -k $WORKSPACE/contrail-operator/deploy/kustomize/contrail/1node/latest

}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    check_pods_active && check_tf_active
}

run_stages $STAGE
