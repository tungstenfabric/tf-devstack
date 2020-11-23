#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build k8s manifest tf wait logs" \
    ["default"]="k8s manifest tf wait" \
    ["master"]="build k8s manifest tf wait" \
    ["platform"]="k8s" \
)

# constants
export DEPLOYER='k8s_manifests'
# max wait in seconds after deployment
export WAIT_TIMEOUT=1200
deployer_image=tf-container-builder-src
deployer_dir=${WORKSPACE}/tf-container-builder
AGENT_LABEL="node-role.opencontrail.org/agent="

# default env variables

KUBE_MANIFEST=${KUBE_MANIFEST:-$deployer_dir/kubernetes/manifests/contrail-standalone-kubernetes.yaml}
CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

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

function manifest() {
    fetch_deployer $deployer_image $deployer_dir || old_k8s_fetch_deployer
    CONTRAIL_REGISTRY=$CONTAINER_REGISTRY \
    CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG \
    HOST_IP=$NODE_IP \
    JVM_EXTRA_OPTS="-Xms1g -Xmx2g" \
    LINUX_DISTR=$DISTRO \
    CLOUD_ORCHESTRATOR=kubernetes \
    KUBERNETES_PUBLIC_FIP_POOL="{'project' : 'k8s-default', 'domain': 'default-domain', 'name': '__fip_pool_public__' , 'network' : '__public__'}" \
    KUBERNETES_IP_FABRIC_SNAT='true' \
    KUBERNETES_IP_FABRIC_FORWARDING='false' \
    CONTROLLER_NODES=${CONTROLLER_NODES// /,} \
    AGENT_NODES=${AGENT_NODES// /,} \
    $deployer_dir/kubernetes/manifests/resolve-manifest.sh $KUBE_MANIFEST > $WORKSPACE/contrail.yaml
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

    # apply manifests
    kubectl apply -f $WORKSPACE/contrail.yaml

    # show results
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
    echo "Use admin/contrail123 to log in"
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
    cp $WORKSPACE/contrail.yaml ${TF_LOG_DIR}/
    collect_logs_from_machines
}

run_stages $STAGE
