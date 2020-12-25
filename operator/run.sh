#!/bin/bash -e

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
    ["all"]="build k8s tf wait logs" \
    ["default"]="k8s tf wait" \
    ["platform"]="k8s" \
)

# constants
export DEPLOYER='operator'
# max wait in seconds after deployment
export WAIT_TIMEOUT=1200

# default env variables

KUBE_MANIFEST=${KUBE_MANIFEST:-$deployer_dir/kubernetes/manifests/contrail-standalone-kubernetes.yaml}
CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function k8s() {
    export K8S_NODES="$AGENT_NODES"
    export K8S_MASTERS="$CONTROLLER_NODES"
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
    $my_dir/../common/deploy_kubespray.sh
}

function build() {
    "$my_dir/../common/dev_env.sh"
}

function tf() {
    # prepare repos
    [ ! -d "$WORKSPACE/tf-operator" ] && git clone http://github.com/progmaticlab/tf-operator.git $WORKSPACE/tf-operator
    [ ! -d "$WORKSPACE/tf-operator-containers" ] && git clone http://github.com/progmaticlab/tf-operator-containers.git $WORKSPACE/tf-operator-containers

    # Build tf-operator and CRDs container
    cd tf-operator
    ./scripts/setup_build_software.sh
    # source profile or relogin for add /usr/local/go/bin to the PATH
    source ~/.bash_profile 

    sudo usermod -a -G docker centos
    newgrp docker << EOF 
    ./scripts/build.sh
EOF

    # Build tf provisioner and statusmonitor containers and push them to local registry
    cd ../tf-operator-containers
    WORKSPACE=$PWD
    ./scripts/setup_build_tools.sh
    ./scripts/build.sh

    # Run tf-operator and AIO Tungsten fabric cluster
    cd ../tf-operator
    WORKSPACE=$PWD
    ./scripts/run_operator.sh
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    check_pods_active
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}

function collect_logs() {
    collect_logs_from_machines
}

run_stages $STAGE
