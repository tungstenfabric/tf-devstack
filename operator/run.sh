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
export DOMAIN=${DOMAIN:-'k8s'}
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
    if [[ "$DISTRO" == "centos" ]]; then
        if ! sudo yum repolist | grep -q epel ; then
            sudo yum -y install epel-release
            parallel_run set_timeserver_node
        fi
        sudo yum install -y jq bind-utils git
    elif [[ "$DISTRO" == "rhel" ]]; then
        sudo yum install -y jq bind-utils git
        parallel_run rhel_setup_node
    elif [ "$DISTRO" == "ubuntu" ]; then
        export DEBIAN_FRONTEND=noninteractive
        sudo -E apt-get update
        sudo -E apt-get install -y jq dnsutils
    else
        echo "Unsupported OS version"
        exit 1
    fi
    sync_time
    if [[ -n "$K8S_CA" ]]; then
        #set_domain_on_machines $DOMAIN
        if [[ "$K8S_CA" == "ipa" ]] && [[ "$DEPLOY_IPA_SERVER" == "true" ]]; then
            ipa_node=$(echo "$IPA_NODES" | cut -d ',' -f1)
            IPA_ADMIN=admin
            IPA_IP=$ipa_node
            ipa_server_install $ipa_node
        fi
        ${K8S_CA}_enroll
    fi
}

function k8s() {
    export K8S_NODES="$AGENT_NODES"
    export K8S_MASTERS="$CONTROLLER_NODES"
    export K8S_POD_SUBNET=$TF_POD_SUBNET
    export K8S_SERVICE_SUBNET=$TF_SERVICE_SUBNET
    export K8S_CLUSTER_NAME=${K8S_CLUSTER_NAME:-'k8s'}
    export K8S_DOMAIN=${DOMAIN:-'k8s'}

    if [[ "${CONTRAIL_CONTAINER_TAG,,}" =~ r2011 || "${CONTRAIL_CONTAINER_TAG,,}" =~ r21\.3 ]] ; then
        export K8S_VERSION="v1.20.15"
    fi
    echo "INFO: use k8s $K8S_VERSION for tag() $CONTRAIL_CONTAINER_TAG"

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
    ensure_kube_api_ready

    # apply crds
    kubectl apply -f $OPERATOR_REPO/deploy/crds/

    wait_cmd_success 'kubectl wait crds --for=condition=Established --timeout=2m managers.tf.tungsten.io' 1 2

    # apply operator
    kubectl apply -k $OPERATOR_REPO/deploy/kustomize/operator/templates/

    # apply contrail cluster
    kubectl apply -k $OPERATOR_REPO/deploy/kustomize/contrail/templates/

    echo "INFO: $(date): wait for vhost0 is up.."
    if ! wait_cmd_success "wait_vhost0_up ${CONTROLLER_NODES}, ${AGENT_NODES}" 5 24; then
        echo "ERROR: vhost0 interface(s) cannot obtain an IP address"
        return 1
    fi
    echo "INFO: $(date): wait for vhost0 is up...done"
    sync_time
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
    if [[ "$CERT_SIGNER" == "External" ]]; then
        DEPLOYMENT_ENV['SSL_KEY']=$(cat /etc/contrail/ssl/certs/server-key-*.pem | base64 -w 0)
        DEPLOYMENT_ENV['SSL_CERT']=$(cat /etc/contrail/ssl/certs/server-*.crt | base64 -w 0)
        DEPLOYMENT_ENV['SSL_CACERT']=$(cat /etc/contrail/ssl/ca-certs/ca-bundle.crt | base64 -w 0)
        CONTROLLER_NODES=$(convert_ips_to_hostnames "$CONTROLLER_NODES")
        AGENT_NODES=$(convert_ips_to_hostnames "$AGENT_NODES")
    else
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
    fi
}

function collect_logs() {
    collect_logs_from_machines
}

run_stages $STAGE
