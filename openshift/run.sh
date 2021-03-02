#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

source "$my_dir/functions.sh"

# stages declaration
declare -A STAGES=( \
    ["all"]="machines manifest tf wait logs" \
    ["default"]="machines manifest tf wait" \
    ["platform"]="machines" \
)

# constants
export DEPLOYER='openshift'
export SSL_ENABLE="true"
export PROVIDER=${PROVIDER:-"kvm"}

export KUBERNETES_CLUSTER_NAME=${KUBERNETES_CLUSTER_NAME:-"test1"}
export KUBERNETES_CLUSTER_DOMAIN=${KUBERNETES_CLUSTER_DOMAIN:-"example.com"}

export KEEP_SOURCES=${KEEP_SOURCES:-false}
export OPERATOR_REPO=${OPERATOR_REPO:-$WORKSPACE/tf-operator}
export OPENSHIFT_REPO=${OPENSHIFT_REPO:-$WORKSPACE/tf-openshift}
export INSTALL_DIR=${INSTALL_DIR:-"${WORKSPACE}/install-${KUBERNETES_CLUSTER_NAME}"}
export KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig"

# user for coreos is always 'core'
export OPENSHIFT_PUB_KEY="${HOME}/.ssh/id_rsa.pub"
export OPENSHIFT_SSH_KEY="${HOME}/.ssh/id_rsa"
export SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no"

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function machines() {
    ${my_dir}/providers/${PROVIDER}/destroy_cluster.sh

    set_ssh_keys

    ${my_dir}/providers/${PROVIDER}/install_openshift.sh
    wait_cmd_success "./oc get pods" 15 480
}

# copy-paste from operator deployer
function manifest() {
    # when Jenkins runs it on same slave - we have to clear previous copy
    if [[ ${KEEP_SOURCES,,} != 'true' ]]; then
        rm -rf $OPERATOR_REPO $OPENSHIFT_REPO
    fi

    # get tf-operator
    if [[ ! -d $OPERATOR_REPO ]] ; then
        fetch_deployer_no_docker tf-operator-src $OPERATOR_REPO \
            || git clone https://github.com/tungstenfabric/tf-operator.git $OPERATOR_REPO
    fi

    # TODO: create and use tf-openshift image
    if [[ ! -d $OPENSHIFT_REPO ]]; then
        git clone https://github.com/tungstenfabric/tf-openshift.git $OPENSHIFT_REPO
    fi

    # prepare kustomize for operator
    process_manifest $OPERATOR_REPO/deploy/kustomize/operator/templates
    process_manifest $OPERATOR_REPO/deploy/kustomize/contrail/templates
}

function tf() {
    echo "INFO: apply CRD-s  $(date)"
    ./oc apply -f ${OPERATOR_REPO}/deploy/crds/

    echo "INFO: wait for CRD-s  $(date)"
    ./oc wait crds --for=condition=Established --timeout=2m managers.contrail.juniper.net

    echo "INFO: apply operator and TF templates  $(date)"
    # apply operator
    wait_cmd_success "./oc apply -k ${OPERATOR_REPO}/deploy/kustomize/operator/templates/" 5 60
    # apply TF cluster
    wait_cmd_success "./oc apply -k ${OPERATOR_REPO}/deploy/kustomize/contrail/templates/" 5 60

    echo "INFO: wait for bootstrap complete  $(date)"
    ./openshift-install --dir=${INSTALL_DIR} wait-for bootstrap-complete

    echo "INFO: destroy bootstrap  $(date)"
    ${my_dir}/providers/${PROVIDER}/destroy_bootstrap.sh

    echo "INFO: approve certs  $(date)"
    # TODO: rework to use 'wait_cmd_success'
    nodes_ready=0
    controller_count=$(echo $CONTROLLER_NODES | wc -w)
    agent_count=$(echo $AGENT_NODES | wc -w)
    nodes_total=$(( $controller_count + $agent_count ))
    while true; do
        nodes_ready=$(./oc get nodes | grep 'Ready' | wc -l)
        for csr in $(./oc get csr 2> /dev/null | grep -w 'Pending' | awk '{print $1}'); do
            ./oc adm certificate approve "$csr" 2> /dev/null || true
            output_delay=0
        done
        [[ "$nodes_ready" -ge "$nodes_total" ]] && break
        sleep 15
    done

    echo "INFO: wait for ingress controller  $(date)"
    wait_cmd_success "./oc get ingresscontroller default -n openshift-ingress-operator -o name" 15 60

    echo "INFO: patch ingress controller  $(date)"
    ./oc patch ingresscontroller default -n openshift-ingress-operator \
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

    # TODO: move it to wait stage
    echo "INFO: wait for install complete  $(date)"
    ./openshift-install --dir=${INSTALL_DIR} wait-for install-complete

    export CONTROLLER_NODES="`./oc get nodes -o wide | awk '/ master /{print $6}' | tr '\n' ' '`"
    echo "INFO: controller_nodes: $CONTROLLER_NODES"
    export AGENT_NODES="`./oc get nodes -o wide | awk '/ worker /{print $6}' | tr '\n' ' '`"
    echo "INFO: agent_nodes: $AGENT_NODES"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    check_kubernetes_resources_active statefulset.apps ./oc && \
    check_kubernetes_resources_active deployment.apps ./oc && \
    check_pods_active ./oc && \
    check_tf_active
}

function collect_deployment_env() {
    if ! is_after_stage 'wait' ; then
        return 0
    fi

    export CONTROLLER_NODES="`./oc get nodes -o wide | awk '/ master /{print $6}' | tr '\n' ' '`"
    echo "INFO: controller_nodes: $CONTROLLER_NODES"
    export AGENT_NODES="`./oc get nodes -o wide | awk '/ worker /{print $6}' | tr '\n' ' '`"
    echo "INFO: agent_nodes: $AGENT_NODES"

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
