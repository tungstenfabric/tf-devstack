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
    ["all"]="build machines k8s tf wait logs" \
    ["default"]="machines k8s manifest tf wait" \
    ["platform"]="machines k8s" \
)

# constants
export DEPLOYER='operator'
export SSL_ENABLE="true"
export OPERATOR_REPO=${OPERATOR_REPO:-$WORKSPACE/tf-operator}
# max wait in seconds after deployment
export WAIT_TIMEOUT=1200

# default env variables

CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function machines() {
    sudo yum -y install epel-release
    sudo yum install -y jq bind-utils git
}

function k8s() {
    export K8S_NODES="$AGENT_NODES"
    export K8S_MASTERS="$CONTROLLER_NODES"
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
    export K8S_CLUSTER_NAME=k8s
    $my_dir/../common/deploy_kubespray.sh
}

function build() {
    "$my_dir/../common/dev_env.sh"
}

function _process_manifest() {
    local folder=$1
    local templates_to_render=`ls $folder/*.j2`
    local template
    for template in $templates_to_render ; do
        local rendered_yaml=$(echo "${template%.*}")
        "$my_dir/../common/jinja2_render.py" < $template > $rendered_yaml
    done
}

function manifest() {
    # get tf-operator
    if [[ ! -d $OPERATOR_REPO ]] ; then
        fetch_deployer_no_docker $tf_operator_image $OPERATOR_REPO \
            || git clone https://github.com/tungstenfabric/tf-operator $OPERATOR_REPO
    fi

    _process_manifest $OPERATOR_REPO/deploy/kustomize/operator/templates
    _process_manifest $OPERATOR_REPO/deploy/kustomize/contrail/templates
}

function tf() {
    sync_time
    ensure_kube_api_ready

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
    check_kubernetes_resources_active statefulset.apps && \
    check_kubernetes_resources_active deployment.apps && \
    check_pods_active && \
    check_tf_active
}

function collect_deployment_env() {
    if ! is_after_stage 'wait' ; then
        return 0
    fi

    # always ssl enabled
    DEPLOYMENT_ENV['SSL_ENABLE']='true'
    # use first pod cert
    local sts="$(kubectl get pod  -n contrail -o json config1-config-statefulset-0)"
    local podIP=$(echo "$sts" | jq -c -r ".status.podIP")
    local podSercret=$(kubectl get secret -n contrail -o json config1-secret-certificates)
    DEPLOYMENT_ENV['SSL_KEY']=$(echo "$podSercret" | jq -c -r ".data.\"server-key-${podIP}.pem\"")
    DEPLOYMENT_ENV['SSL_CERT']=$(echo "$podSercret" | jq -c -r ".data.\"server-${podIP}.crt\"")
    DEPLOYMENT_ENV['SSL_CACERT']=$(kubectl get secrets -n contrail contrail-ca-certificate -o json | jq -c -r  ".data.\"ca-bundle.crt\"")
}

function collect_logs() {
    collect_logs_from_machines
}

run_stages $STAGE
