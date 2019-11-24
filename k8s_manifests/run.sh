#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"

# stages declaration

declare -a all_stages=(build kubernetes manifest tf wait)

# constants

DEPLOYER_IMAGE="contrail-k8s-manifests"
DEPLOYER_DIR="contrail-container-builder"
AGENT_LABEL="node-role.opencontrail.org/agent="

# default env variables

KUBE_MANIFEST=${KUBE_MANIFEST:-$WORKSPACE/$DEPLOYER_DIR/kubernetes/manifests/contrail-standalone-kubernetes.yaml}
CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

# stages

function build() {
    echo "INFO: Building TF $(date)"
    #"$my_dir/../common/dev_env.sh"
}

function k8s() {
    echo "INFO: Deploying kubespray  $(date)"
    export K8S_NODES=$AGENT_NODES
    export K8S_MASTERS=$CONTROLLER_NODES
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
    $my_dir/../common/deploy_kubespray.sh
}

function manifest() {
    echo "INFO: Creating manifest contrail.yaml"
    fetch_deployer
    export CONTRAIL_REGISTRY=$CONTAINER_REGISTRY
    export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG
    export HOST_IP=$NODE_IP
    export JVM_EXTRA_OPTS="-Xms1g -Xmx2g"
    export LINUX_DISTR=$DISTRO
    $WORKSPACE/$DEPLOYER_DIR/kubernetes/manifests/resolve-manifest.sh $KUBE_MANIFEST > contrail.yaml
}

function tf() {
    echo "INFO: Deploying TF $(date)"
    ensure_insecure_registry_set $CONTAINER_REGISTRY
    ensure_kube_api_ready

    # label nodes
    labels=( $(grep "key: \"node-role." contrail.yaml | tr -s [:space:] | sort -u | cut -d: -f2 | tr -d \") )
    label_nodes_by_ip $AGENT_LABEL $AGENT_NODES
    for label in ${labels[@]}
    do
        label_nodes_by_ip "$label=" $CONTROLLER_NODES
    done

    # apply manifests
    kubectl apply -f contrail.yaml

    # show results
    echo "TF deployment scripts are finished $(date)"
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    eval check_pods_active && eval check_tf_active
}

if [[ -z "$STAGE" ]] || [[ "$STAGE" == "deploy" ]] ; then
    stages="k8s manifest tf wait"
elif [[ "$STAGE" == "master" ]]; then
    stages="build k8s manifest tf wait"
else
    # run selected stage
    stages="$STAGE"
fi

run_stages $stages
