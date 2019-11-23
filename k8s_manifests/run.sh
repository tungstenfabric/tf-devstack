#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

# stages declaration

STAGE=$1
[[ -n $2 ]] && shift && OPTIONS="$@"
declare -a all_stages=(build kubernetes manifest contrail)

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

function kubernetes() {
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
    echo "INFO: Deploying TF"
    ensure_insecure_registry_set $CONTAINER_REGISTRY
    ensure_kube_api_ready

    # label nodes
    labels=( $(grep "key: \"node-role." contrail.yaml | tr -s [:space:] | sort -u | cut -d: -f2 | tr -d \") )
    label_nodes_by_ip $AGENT_LABEL $AGENT_NODES
    for label in ${labels[@]}
    do
        label_nodes_by_ip $label $CONTROLLER_NODES
    done

    # apply manifests
    kubectl apply -f contrail.yaml

    # safe tf stack profile

    save_tf_stack_profile

    # show results
    echo "Deployment scripts are finished"
    echo "Now you can monitor when contrail becomes available with:"
    echo "kubectl get pods --all-namespaces"
    echo "All pods should become Running before you can use Contrail"
    echo "If agent is in Error state you might need to upgrade your kernel with 'sudo yum update -y' and reboot the node"
    echo "If agent is in a permanent CrashLoopBackOff state and other Contrail containers are Running, please reboot the node"
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
}

# build step

load_tf_devenv_profile

if [[ -z "$STAGE" ]] || [[ "$STAGE" == "deploy" ]] ; then
    stages="kubernetes manifest tf"
elif [[ "$STAGE" == "master" ]]; then
    stages="build kubernetes manifest tf"
else
    # run selected stage
    stages="$STAGE"
fi

echo "INFO: Applying stages ${stages[@]}"
for stage in ${stages[@]} ; do
    run_stage $stage $OPTIONS
done

echo "INFO: Successful deployment $(date)"
