#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

source "$my_dir/functions.sh"

export PATH="$HOME:$PATH"

# stages declaration
declare -A STAGES=( \
    ["all"]="machines manifest tf wait logs" \
    ["default"]="machines manifest tf wait" \
    ["platform"]="machines" \
)

# constants

# supported version 4.5, 4.6, master
# master is a laltest supported numerical version
export OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-'master'}
if [[ "$OPENSHIFT_VERSION" == 'master' ]]; then
    export OPENSHIFT_VERSION='4.6'
fi

export DEPLOYER='openshift'
export SSL_ENABLE="true"
export PROVIDER=${PROVIDER:-"kvm"}

export KUBERNETES_CLUSTER_NAME=${KUBERNETES_CLUSTER_NAME:-"test1"}
export KUBERNETES_CLUSTER_DOMAIN=${KUBERNETES_CLUSTER_DOMAIN:-"example.com"}

export CONFIGDB_MIN_HEAP_SIZE=${CONFIGDB_MIN_HEAP_SIZE:-"1g"}
export CONFIGDB_MAX_HEAP_SIZE=${CONFIGDB_MAX_HEAP_SIZE:-"4g"}

export KEEP_SOURCES=${KEEP_SOURCES:-false}
export OPERATOR_REPO=${OPERATOR_REPO:-$WORKSPACE/tf-operator}
export OPENSHIFT_REPO=${OPENSHIFT_REPO:-$WORKSPACE/tf-openshift}
export INSTALL_DIR=${INSTALL_DIR:-"${WORKSPACE}/install-${KUBERNETES_CLUSTER_NAME}"}
export KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig"

# user for coreos is always 'core'
export OPENSHIFT_PUB_KEY="${HOME}/.ssh/id_rsa.pub"
export OPENSHIFT_SSH_KEY="${HOME}/.ssh/id_rsa"
export SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no"

unset CONTROLLER_SERVICES['config-database']
CONTROLLER_SERVICES['config']+="dnsmasq "
CONTROLLER_SERVICES['_']+="rabbitmq stunnel zookeeper "

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function machines() {
    echo "$DISTRO detected"
    if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
        sudo yum -y install epel-release
        sudo yum install -y python3 python3-setuptools iproute jq bind-utils git
    elif [ "$DISTRO" == "ubuntu" ]; then
        export DEBIAN_FRONTEND=noninteractive
        sudo -E apt-get update
        sudo -E apt-get install -y python-setuptools python3-distutils iproute2 python-crypto jq dnsutils
    else
        echo "Unsupported OS version"
        exit 1
    fi

    ${my_dir}/providers/${PROVIDER}/destroy_cluster.sh

    set_ssh_keys
}

# copy-paste from operator deployer
function manifest() {
    # when Jenkins runs it on same slave - we have to clear previous copy
    if [[ ${KEEP_SOURCES,,} != 'true' ]]; then
        rm -rf $OPERATOR_REPO $OPENSHIFT_REPO
    fi

    # get tf-operator
    if [[ ! -d $OPERATOR_REPO ]] ; then
        if ! fetch_deployer_no_docker tf-operator-src $OPERATOR_REPO ; then
            echo "WARNING: failed to fetch tf-operator-src, use github"
            git clone https://github.com/tungstenfabric/tf-operator.git $OPERATOR_REPO
        fi
    fi

    # get tf-openshift
    if [[ ! -d $OPENSHIFT_REPO ]]; then
        if ! fetch_deployer_no_docker tf-openshift-src $OPENSHIFT_REPO ; then
            echo "WARNING: failed to fetch tf-openshift-src, use github"
            git clone https://github.com/tungstenfabric/tf-openshift.git $OPENSHIFT_REPO
        fi
    fi

    # prepare kustomize for operator
    $OPERATOR_REPO/contrib/render_manifests.sh
}

function _patch_ingress_controller() {
    local controller_count=$1
    oc patch ingresscontroller default -n openshift-ingress-operator \
        --type merge \
        --patch '{
            "spec":{
                "replicas": '${controller_count}',
                "nodePlacement":{
                    "nodeSelector":{
                        "matchLabels":{
                            "node-role.kubernetes.io/master":""
                        }
                    },
                    "tolerations":[{
                        "effect": "NoSchedule",
                        "operator": "Exists"
                    }]
                }
            }
        }'
}

function _monitor_csr() {
    local csr
    while true; do
        for csr in $(oc get csr 2> /dev/null | grep -w 'Pending' | awk '{print $1}'); do
            echo "INFO: csr monitor: approve $csr"
            oc adm certificate approve "$csr" 2> /dev/null || true
        done
        sleep 5
    done
}

function tf() {
    # TODO: somehow move machine creation to machines
    ${my_dir}/providers/${PROVIDER}/install_openshift.sh
    wait_cmd_success "oc get pods" 15 480

    echo "INFO: apply CRD-s  $(date)"
    wait_cmd_success "oc apply -f ${OPERATOR_REPO}/deploy/crds/" 5 60

    echo "INFO: wait for CRD-s  $(date)"
    wait_cmd_success 'oc wait crds --for=condition=Established --timeout=2m managers.tf.tungsten.io' 1 2

    echo "INFO: apply operator and TF templates  $(date)"
    # apply operator
    wait_cmd_success "oc apply -k ${OPERATOR_REPO}/deploy/kustomize/operator/templates/" 5 60
    # apply TF cluster
    wait_cmd_success "oc apply -k ${OPERATOR_REPO}/deploy/kustomize/contrail/templates/" 5 60

    echo "INFO: wait for bootstrap complete  $(date)"
    ./openshift-install --dir=${INSTALL_DIR} wait-for bootstrap-complete

    echo "INFO: destroy bootstrap  $(date)"
    ${my_dir}/providers/${PROVIDER}/destroy_bootstrap.sh

    echo "INFO: start approve certs thread $(date)"
    _monitor_csr &
    mpid=$!

    echo "INFO: wait for ingress controller  $(date)"
    wait_cmd_success "oc get ingresscontroller default -n openshift-ingress-operator -o name" 15 60

    echo "INFO: patch ingress controller  $(date)"
    wait_cmd_success "_patch_ingress_controller ${controller_count}" 3 10

    # TODO: move it to wait stage
    echo "INFO: wait for install complete $(date)"
    ./openshift-install --dir=${INSTALL_DIR} wait-for install-complete

    echo "INFO: stop csr approving monitor: pid=$mpid"
    kill $mpid
    wait $mpid
    echo "INFO: csr approving monitor stopped"

    export CONTROLLER_NODES="`oc get nodes -o wide | awk '/ master /{print $6}' | tr '\n' ' '`"
    echo "INFO: controller_nodes: $CONTROLLER_NODES"
    export AGENT_NODES="`oc get nodes -o wide | awk '/ worker /{print $6}' | tr '\n' ' '`"
    echo "INFO: agent_nodes: $AGENT_NODES"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    check_kubernetes_resources_active statefulset.apps oc && \
    check_kubernetes_resources_active deployment.apps oc && \
    check_pods_active oc && \
    check_tf_active core && \
    check_tf_services core
}

function collect_deployment_env() {
    if ! is_after_stage 'wait' ; then
        return 0
    fi

    export CONTROLLER_NODES="`oc get nodes -o wide | awk '/ master /{print $6}' | tr '\n' ' '`"
    echo "INFO: controller_nodes: $CONTROLLER_NODES"
    export AGENT_NODES="`oc get nodes -o wide | awk '/ worker /{print $6}' | tr '\n' ' '`"
    echo "INFO: agent_nodes: $AGENT_NODES"

    # always ssl enabled
    DEPLOYMENT_ENV['SSL_ENABLE']='true'
    # use first pod cert
    local sts="$(oc get pod  -n contrail -o json config1-config-statefulset-0)"
    local podIP=$(echo "$sts" | jq -c -r ".status.podIP")
    local podSercret=$(oc get secret -n contrail -o json config1-secret-certificates)
    DEPLOYMENT_ENV['SSL_KEY']=$(echo "$podSercret" | jq -c -r ".data.\"server-key-${podIP}.pem\"")
    DEPLOYMENT_ENV['SSL_CERT']=$(echo "$podSercret" | jq -c -r ".data.\"server-${podIP}.crt\"")
    DEPLOYMENT_ENV['SSL_CACERT']=$(oc get secrets -n contrail contrail-ca-certificate -o json | jq -c -r  ".data.\"ca-bundle.crt\"")
}

function collect_logs() {
    collect_logs_from_machines
}

run_stages $STAGE
