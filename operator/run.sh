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
    ["all"]="build machines k8s manifest tf wait logs" \
    ["default"]="machines k8s manifest tf wait" \
    ["platform"]="machines k8s" \
)

# constants
export KEEP_SOURCES=${KEEP_SOURCES:-false}
export DEPLOYER='operator'
export SSL_ENABLE="true"
export OPERATOR_REPO=${OPERATOR_REPO:-$WORKSPACE/tf-operator}
# max wait in seconds after deployment
export WAIT_TIMEOUT=1200

unset CONTROLLER_SERVICES['config-database']
CONTROLLER_SERVICES['config']+="dnsmasq "
CONTROLLER_SERVICES['_']+="rabbitmq stunnel zookeeper "

# default env variables

TF_POD_SUBNET=${TF_POD_SUBNET:-"10.32.0.0/12"}
TF_SERVICE_SUBNET=${TF_SERVICE_SUBNET:-"10.96.0.0/12"}

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function machines() {
    echo "$DISTRO detected"
    if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
        sudo yum -y install epel-release
        sudo yum install -y jq bind-utils git
    elif [ "$DISTRO" == "ubuntu" ]; then
        export DEBIAN_FRONTEND=noninteractive
        sudo -E apt-get update
        sudo -E apt-get install -y jq dnsutils
    else
        echo "Unsupported OS version"
        exit 1
    fi
}

function k8s() {
    export K8S_NODES="$AGENT_NODES"
    export K8S_MASTERS="$CONTROLLER_NODES"
    export K8S_POD_SUBNET=$TF_POD_SUBNET
    export K8S_SERVICE_SUBNET=$TF_SERVICE_SUBNET
    export K8S_CLUSTER_NAME=k8s
    $my_dir/../common/deploy_kubespray.sh
}

function build() {
    "$my_dir/../common/dev_env.sh"
}

function manifest() {
    if [[ ${KEEP_SOURCES,,} != 'true' ]]; then
        rm -rf $OPERATOR_REPO
    fi
    if [[ ! -d $OPERATOR_REPO ]] ; then
        if ! fetch_deployer_no_docker $tf_operator_image $OPERATOR_REPO ; then
            echo "WARNING: failed to fetch $tf_operator_image, use github"
            git clone https://github.com/tungstenfabric/tf-operator $OPERATOR_REPO
        fi
    fi
    export CONFIGDB_MIN_HEAP_SIZE=${CONFIGDB_MIN_HEAP_SIZE:-"1g"}
    export CONFIGDB_MAX_HEAP_SIZE=${CONFIGDB_MAX_HEAP_SIZE:-"4g"}
    export ANALYTICSDB_MIN_HEAP_SIZE=${ANALYTICSDB_MIN_HEAP_SIZE:-"1g"}
    export ANALYTICSDB_MAX_HEAP_SIZE=${ANALYTICSDB_MAX_HEAP_SIZE:-"4g"}
    $OPERATOR_REPO/contrib/render_manifests.sh
}

function tf() {
    sync_time
    ensure_kube_api_ready

    # apply crds
    kubectl apply -f $OPERATOR_REPO/deploy/crds/

    wait_cmd_success 'kubectl wait crds --for=condition=Established --timeout=2m managers.tf.tungsten.io' 1 2

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
    check_tf_active && \
    check_tf_services
}

function collect_deployment_env() {
    if ! is_after_stage 'wait' ; then
        return 0
    fi

    # always ssl enabled
    DEPLOYMENT_ENV['SSL_ENABLE']='true'
    # use first pod cert
    local sts="$(kubectl get pod  -n tf -o json config1-config-statefulset-0)"
    local podIP=$(echo "$sts" | jq -c -r ".status.podIP")
    local podSercret=$(kubectl get secret -n tf -o json config1-secret-certificates)
    DEPLOYMENT_ENV['SSL_KEY']=$(echo "$podSercret" | jq -c -r ".data.\"server-key-${podIP}.pem\"")
    DEPLOYMENT_ENV['SSL_CERT']=$(echo "$podSercret" | jq -c -r ".data.\"server-${podIP}.crt\"")
    DEPLOYMENT_ENV['SSL_CACERT']=$(kubectl get secrets -n tf contrail-ca-certificate -o json | jq -c -r  ".data.\"ca-bundle.crt\"")
}

function collect_logs() {
    collect_logs_from_machines
}

run_stages $STAGE
