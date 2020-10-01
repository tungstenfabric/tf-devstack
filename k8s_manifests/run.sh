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
    ["testw"]="wait" \
)

# constants
export DEPLOYER='k8s_manifests'
# max wait in seconds after deployment
export WAIT_TIMEOUT=600
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

function logs() {
    local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
    set +e
    create_log_dir
    cp $WORKSPACE/contrail.yaml ${TF_LOG_DIR}/

    cat <<EOF >/tmp/logs.sh
#!/bin/bash
tgz_name=\$1
export WORKSPACE=/tmp/k8s_manifests-logs
export TF_LOG_DIR=/tmp/k8s_manifests-logs/logs
export SSL_ENABLE=$SSL_ENABLE
cd /tmp/k8s_manifests-logs
source ./collect_logs.sh
collect_system_stats
collect_contrail_status
collect_docker_logs
collect_kubernetes_objects_info
collect_kubernetes_logs
collect_contrail_logs
chmod -R a+r logs
pushd logs
tar -czf \$tgz_name *
popd
cp logs/\$tgz_name \$tgz_name
rm -rf logs
EOF
    chmod a+x /tmp/logs.sh

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local machine
    for machine in $(echo "$CONTROLLER_NODES $AGENT_NODES" | tr " " "\n" | sort -u) ; do
        local tgz_name="logs-$machine.tgz"
        mkdir -p $TF_LOG_DIR/$machine
        ssh $ssh_opts $machine "mkdir -p /tmp/k8s_manifests-logs"
        scp $ssh_opts $my_dir/../common/collect_logs.sh $machine:/tmp/k8s_manifests-logs/collect_logs.sh
        scp $ssh_opts /tmp/logs.sh $machine:/tmp/k8s_manifests-logs/logs.sh
        ssh $ssh_opts $machine /tmp/k8s_manifests-logs/logs.sh $tgz_name
        scp $ssh_opts $machine:/tmp/k8s_manifests-logs/$tgz_name $TF_LOG_DIR/$machine/
        pushd $TF_LOG_DIR/$machine/
        tar -xzf $tgz_name
        rm -rf $tgz_name
        popd
    done

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    rm -rf $TF_LOG_DIR

    # Restore errexit state
    if [[ $errexit_state == 1 ]]; then
        set -e
    fi
}

function k8s() {
    export K8S_NODES="$AGENT_NODES"
    export K8S_MASTERS="$CONTROLLER_NODES"
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
    $my_dir/../common/deploy_kubespray.sh
}

# There are three fetch_deployer functions/methods now:
# - fetch_deployer_no_docker - the most advanced function - fetch deployer src container without installing docker. In the future she will replace all the others
# - fetch_deployer - function fetch deployer src container using docker. Needs docker to be installed on host
# - old_XXX_fetch_deployer - deprecated deployer method saved for backward compatibility. Will be removed in the future.

function old_k8s_fetch_deployer() {
    local deployer_image="contrail-k8s-manifests"
    local deployer_dir="$WORKSPACE/tf-container-builder"
    local image="$CONTAINER_REGISTRY/$deployer_image"
    sudo rm -rf $deployer_dir
    [ -n "$CONTRAIL_CONTAINER_TAG" ] && image+=":$CONTRAIL_CONTAINER_TAG"
    sudo docker create --name $deployer_image --entrypoint /bin/true $image
    sudo docker cp $deployer_image:contrail-container-builder $deployer_dir
    sudo docker rm -fv $deployer_image
}

function manifest() {
    fetch_deployer $deployer_image $deployer_dir || old_k8s_fetch_deployer
    export CONTRAIL_REGISTRY=$CONTAINER_REGISTRY
    export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG
    export HOST_IP=$NODE_IP
    export JVM_EXTRA_OPTS="-Xms1g -Xmx2g"
    export LINUX_DISTR=$DISTRO
    export KUBERNETES_PUBLIC_FIP_POOL="{'project' : 'k8s-default', 'domain': 'default-domain', 'name': '__fip_pool_public__' , 'network' : '__public__'}"
    export CONTROLLER_NODES=${CONTROLLER_NODES// /,}
    export AGENT_NODES=${AGENT_NODES// /,}
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
    check_tf_active && check_pods_active
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}

run_stages $STAGE
