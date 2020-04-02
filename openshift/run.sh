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
    ["all"]="build platform tf wait logs" \
    ["default"]="platform tf wait" \
    ["master"]="build platform tf wait" \
    ["platform"]="platform" \
)

# constants
export DEPLOYER='openshift'
export OPENSHIFT_VERSION=${OPENSHIFT_VERSION-"release-3.11-contrail"}

# max wait in seconds after deployment
export WAIT_TIMEOUT=600
deployer_image=tf-openshift-ansible-src
deployer_dir=${WORKSPACE}/tf-openshift-ansible-src

# default env variables

INVENTORY_FILE=${INVENTORY_FILE:-"$deployer_dir/inventory/hosts.aio.contrail"}
CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

settings_file=${WORKSPACE}/tf_openhift_settings
cat <<EOF > $settings_file
[OSEv3:vars]
oreg_url=$RHEL_OPENSHIFT_REGISTRY
oreg_auth_user=$RHEL_USER
oreg_auth_password=$RHEL_PASSWORD
contrail_container_tag="$CONTRAIL_CONTAINER_TAG"
contrail_registry="$CONTAINER_REGISTRY"
service_subnets="$CONTRAIL_SERVICE_SUBNET"
pod_subnets="$CONTRAIL_POD_SUBNET"
#ip_fabric_subnets="10.64.0.0/12"
contrail_analyticsdb_jvm_extra_opts="-Xms2g -Xmx4g"
contrail_configdb_jvm_extra_opts="-Xms1g -Xmx2g"
EOF

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
    collect_system_stats
    collect_contrail_status
    collect_docker_logs
    collect_kubernetes_objects_info
    collect_kubernetes_logs
    collect_contrail_logs

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    rm -rf $TF_LOG_DIR

    # Restore errexit state
    if [[ $errexit_state == 1 ]]; then
        set -e
    fi
}

function platform() {
    sudo yum install -y jq iproute \
        wget git tcpdump net-tools bind-utils yum-utils iptables-services \
        bridge-utils bash-completion kexec-tools sos psacct python-netaddr \
        openshift-ansible

    if ! fetch_deployer_no_docker $deployer_image $deployer_dir ; then
        git clone https://github.com/Juniper/openshift-ansible $deployer_dir
    fi
    cd $deployer_dir
    if [[ -n "$OPENSHIFT_VERSION" ]] ; then 
        git checkout $OPENSHIFT_VERSION
    fi
    sudo ansible-playbook -i $settings_file \
        -i inventory/hosts.aio.contrail playbooks/prerequisites.yml
}

function tf() {
    cd $deployer_dir
    sudo ansible-playbook -i $settings_file \
        -i inventory/hosts.aio.contrail playbooks/deploy_cluster.yml
    # show results
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
    echo "Use admin/contrail123 to log in"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    check_pods_active && check_tf_active
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}

run_stages $STAGE
