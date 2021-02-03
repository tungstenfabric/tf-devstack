#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"
source "$my_dir/functions.sh"

tf_operator_image=tf-operator-src

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build k8s tf wait logs" \
    ["default"]="k8s tf wait" \
    ["platform"]="k8s" \
)

# constants
export DEPLOYER='operator'
export OPERATOR_REPO=${OPERATOR_REPO:-$WORKSPACE/tf-operator}
# max wait in seconds after deployment
export WAIT_TIMEOUT=1200

# default env variables

CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function k8s() {
    sudo yum -y install epel-release
    sudo yum install -y jq bind-utils
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
    # get tf-operator
    [ -d $OPERATOR_REPO ] || fetch_deployer_no_docker $tf_operator_image $OPERATOR_REPO \
                      || git clone https://github.com/tungstenfabric/tf-operator $OPERATOR_REPO

    # prepare kustomize for operator
    local operator_template="$OPERATOR_REPO/deploy/kustomize/operator/templates/kustomization.yaml"
    "$my_dir/../common/jinja2_render.py" < ${operator_template}.j2 > $operator_template

    # prepare kustomize for contrail
    local templates_to_render=`ls $OPERATOR_REPO/deploy/kustomize/contrail/templates/*.j2`
    local template
    for template in $templates_to_render ; do
        local rendered_yaml=$(echo "${template%.*}")
        "$my_dir/../common/jinja2_render.py" < $template > $rendered_yaml
    done

    # apply crds
    kubectl apply -f $OPERATOR_REPO/deploy/crds/

    wait_cmd_success 'kubectl wait crds --for=condition=Established --timeout=2m managers.contrail.juniper.net'

    # apply operator
    kubectl apply -k $OPERATOR_REPO/deploy/kustomize/operator/templates/

    # apply contrail cluster
    kubectl apply -k $OPERATOR_REPO/deploy/kustomize/contrail/templates/
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
