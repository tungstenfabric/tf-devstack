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
export DATA_NETWORK=${DATA_NETWORK}
# max wait in seconds after deployment
export WAIT_TIMEOUT=1200

# default env variables
export TF_POD_SUBNET=${TF_POD_SUBNET:-"10.32.0.0/12"}
export TF_SERVICE_SUBNET=${TF_SERVICE_SUBNET:-"10.96.0.0/12"}

# CA to use
#   default - use operator default
#   openssl - generate own self-signed root CA & key
#   ipa     - IPA
export K8S_CA=${K8S_CA:-}
export IPA_IP=${IPA_IP:-}
export IPA_ADMIN=${IPA_ADMIN:-}
export IPA_PASSWORD=${IPA_PASSWORD:-}

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function machines() {
    echo "$DISTRO detected"
    if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
        if ! sudo yum repolist | grep -q epel ; then
            sudo yum -y install epel-release
        fi
        sudo yum install -y jq bind-utils git
    elif [ "$DISTRO" == "ubuntu" ]; then
        export DEBIAN_FRONTEND=noninteractive
        sudo -E apt-get update
        sudo -E apt-get install -y jq dnsutils
    else
        echo "Unsupported OS version"
        exit 1
    fi
    if [[ -n "$K8S_CA" ]]; then
        if [[ "$K8S_CA" == "ipa" ]] && [[ "$DEPLOY_IPA_SERVER" == "true" ]]; then
            ipa_node=$(echo "$IPA_NODES" | awk '{print $1}')
            IPA_ADMIN=admin
            export IPA_CERT=$(ipa_server_install $ipanode $IPA_PASSWORD)
            IPA_IP=$ipanode
        fi
        ${K8S_CA}_enroll
    fi
}

function k8s() {
    export K8S_NODES="$AGENT_NODES"
    export K8S_MASTERS="$CONTROLLER_NODES"
    export K8S_POD_SUBNET=$TF_POD_SUBNET
    export K8S_SERVICE_SUBNET=$TF_SERVICE_SUBNET
    export K8S_CLUSTER_NAME=k8s

    if [[ "${CONTRAIL_CONTAINER_TAG,,}" =~ '[rR]2011' || "${CONTRAIL_CONTAINER_TAG,,}" =~ '[rR]21\.3' ]] ; then
        export K8S_VERSION="v1.20"
        echo "INFO: use k8s $K8S_VERSION for branches r2011/r21.3"
    fi

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
    export VROUTER_GATEWAY=${VROUTER_GATEWAY:-$(get_vrouter_gateway)}
    if [[ -n $DATA_NETWORK ]] && [[ -z $VROUTER_GATEWAY ]] ; then
        echo "ERROR: for multi-NIC setup VROTER_GATEWAY should be set"
        exit 1
    fi    
    if [[ -n "$SSL_CAKEY" && -n "$SSL_CACERT" ]] ; then
        export TF_ROOT_CA_KEY_BASE64=$(echo "$SSL_CAKEY" | base64 -w 0)
        export TF_ROOT_CA_CERT_BASE64=$(echo "$SSL_CACERT" | base64 -w 0)
    fi
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
    # Services to check in wait stage
    CONTROLLER_SERVICES['config-database']=""
    CONTROLLER_SERVICES['config']+="dnsmasq "
    CONTROLLER_SERVICES['_']+="rabbitmq stunnel zookeeper "
    if [[ "${CNI}" == "calico" ]]; then
        AGENT_SERVICES['vrouter']=""
    fi

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
    local ca_cert="$SSL_CACERT"
    if [ -z "$ca_cert" ] ; then
        ca_cert=$(kubectl get secrets -n tf contrail-ca-certificate -o json | jq -c -r  ".data.\"ca-bundle.crt\"") || true
        if [ -z "$ca_cert" ] ; then
            ca_cert=$(kubectl get configmaps -n kube-public cluster-info -o json | jq -r -c ".data.kubeconfig" | awk  '/certificate-authority-data:/ {print($2)}')
        fi
    fi
    if [ -z "$ca_cert" ] ; then
        echo "ERROR: CA is empty: there is no CA in both contrail-ca-certificate secret and configmaps kube-public/cluster-info"
        exit 1
    fi
    DEPLOYMENT_ENV['SSL_CACERT']="$ca_cert"
}

function collect_logs() {
    collect_logs_from_machines
}

run_stages $STAGE
