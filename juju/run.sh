#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"
source "$my_dir/functions.sh"

tf_charms_image=tf-charms-src

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build juju machines k8s openstack tf wait logs" \
    ["default"]="juju machines k8s openstack tf wait" \
    ["master"]="build juju machines k8s openstack tf wait" \
    ["platform"]="juju machines k8s openstack wait" \
)

export PATH=$PATH:/snap/bin

# default env variables
export DEPLOYER='juju'
# max wait in seconds after deployment (openstack ~ 1300, k8s ~ 2100, maas ~ 2400???3600)
export WAIT_TIMEOUT=${WAIT_TIMEOUT:-3600}
export JUJU_REPO=${JUJU_REPO:-$WORKSPACE/tf-charms}
export ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}  # openstack | kubernetes
export CLOUD=${CLOUD:-manual}  # aws | maas | manual
# cloud local is deprecated, please use CLOUD=manual and unset CONTROLLER_NODES and AGENT_NODES
if [[ $CLOUD == 'local' ]] ; then
    echo "WARNING: cloud 'local is deprecated"
    echo "for deploy to local machine use CLOUD='manual' (by default) and unset CONTROLLER_NODES and AGENT_NODES"
    if [[ ( -n $CONTROLLER_NODES && $CONTROLLER_NODES != $NODE_IP ) ||
          ( -n $AGENT_NODES && $AGENT_NODES != $NODE_IP ) ]] ; then
        echo "ERROR: for local cloud CONTROLLER_NODES and AGENT_NODES must be either empty or contains just host ip"
        exit 1
    fi
    CLOUD='manual'
fi
export CONTROL_NETWORK=${CONTROL_NETWORK:-}
export DATA_NETWORK=${DATA_NETWORK:-}
export ENABLE_DPDK_SRIOV=${ENABLE_DPDK_SRIOV:-'false'}
export AUTH_PASSWORD="password"

AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-''}
AWS_SECRET_KEY=${AWS_SECRET_KEY:-''}
AWS_REGION=${AWS_REGION:-'us-east-1'}

MAAS_ENDPOINT=${MAAS_ENDPOINT:-''}
MAAS_API_KEY=${MAAS_API_KEY:-''}

source /etc/lsb-release
export UBUNTU_SERIES=${UBUNTU_SERIES:-${DISTRIB_CODENAME}}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export VIRT_TYPE=${VIRT_TYPE:-'qemu'}

export CONTAINER_REGISTRY
export NODE_IP
export VIRTUAL_IPS

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=(\
    ['AUTH_URL']=""
    ['AUTH_PORT']="35357"
    ['AUTH_DOMAIN']="admin_domain"
    ['AUTH_PASSWORD']="$AUTH_PASSWORD"
    ['SSH_USER']="ubuntu"
)

function build() {
    "$my_dir/../common/dev_env.sh"
}

function juju() {
    $my_dir/../common/deploy_juju.sh
}

function machines() {
    if [[ $CLOUD == 'manual' ]] ; then
        local count=`echo $CONTROLLER_NODES | awk -F ' ' '{print NF}'`
        if [[ $(( $count % 2 )) -eq 0 ]]; then
            echo "ERROR: controllers amount should be odd. now it is $count."
            exit 1
        fi
        $my_dir/../common/add_juju_machines.sh
    fi
    if [[ $ORCHESTRATOR == 'all' ]] ; then
        # in case k8s is deploying before lxd container creating,
        # lxd have wrong parent in config and can't get IP address
        # to prevent it we starts lxd before
        command juju deploy ubuntu --to lxd:0
    fi

    retry sudo apt-get update -u
    retry sudo apt-get install -y jq dnsutils
}

function openstack() {
    if [[ "$ORCHESTRATOR" != "openstack" && $ORCHESTRATOR != 'all' ]]; then
        echo "INFO: Skipping openstack deployment"
        return
    fi

    if [[ "$UBUNTU_SERIES" == 'bionic' && "$OPENSTACK_VERSION" == 'queens' ]]; then
        export OPENSTACK_ORIGIN="distro"
    elif [[ "$UBUNTU_SERIES" == 'focal' && "$OPENSTACK_VERSION" == 'ussuri' ]]; then
        export OPENSTACK_ORIGIN="distro"
    else
        export OPENSTACK_ORIGIN="cloud:$UBUNTU_SERIES-$OPENSTACK_VERSION"
    fi
    export BUNDLE="$my_dir/files/bundle_openstack.yaml.tmpl"

    if [ $CLOUD == 'maas' ] ; then
        IPS_COUNT=`echo $VIRTUAL_IPS | wc -w`
        if [[ "$IPS_COUNT" != 7 ]] && [[ "$IPS_COUNT" != 1 ]] ; then
            echo "ERROR: We support deploy with 7 virtual ip addresses only now."
            echo "You must specify the first address in the range or all seven IP in VIRTUAL_IPS variable."
            exit 1
        fi
        if [[ "$IPS_COUNT" = 1 ]] ; then
            export VIRTUAL_IPS=$(prips $(netmask ${VIRTUAL_IPS} | tr -d "[:space:]") | \
                grep -P "^${VIRTUAL_IPS%/*}$"  -A6 | tr '\n' ' ')
        fi
        export BUNDLE="$my_dir/files/bundle_openstack_maas_ha.yaml.tmpl"
    fi
    $my_dir/../common/deploy_juju_bundle.sh
}

function k8s() {
    if [[ "$ORCHESTRATOR" != "kubernetes" && $ORCHESTRATOR != 'all' ]]; then
        echo "INFO: Skipping k8s deployment"
        return
    fi
    export BUNDLE="$my_dir/files/bundle_k8s.yaml.tmpl"
    $my_dir/../common/deploy_juju_bundle.sh
}

function tf() {
    if [ $CLOUD == 'maas' ] ; then
        TF_UI_IP=$(command juju show-machine 0 --format tabular | grep '^0\s' | awk '{print $3}')
    fi
    export BUNDLE="$my_dir/files/bundle_contrail.yaml.tmpl"

    # get contrail-charms
    [ -d $JUJU_REPO ] || fetch_deployer_no_docker $tf_charms_image $JUJU_REPO \
                      || git clone https://github.com/tungstenfabric/tf-charms $JUJU_REPO
    cd $JUJU_REPO

    # do not retry hooks during tf deployment
    command juju model-config automatically-retry-hooks=false

    $my_dir/../common/deploy_juju_bundle.sh

    # add relations between orchestrator and Contrail
    if [[ $ORCHESTRATOR == 'openstack' || $ORCHESTRATOR == 'all' ]] ; then
        command juju add-relation contrail-keystone-auth keystone
        command juju add-relation contrail-openstack neutron-api
        command juju add-relation contrail-openstack heat
        if [[ ${ENABLE_DPDK_SRIOV,,} == 'true' ]] ; then
            command juju add-relation contrail-openstack nova-compute-dpdk
            command juju add-relation contrail-agent-dpdk:juju-info nova-compute-dpdk:juju-info
            command juju add-relation contrail-openstack nova-compute-sriov
            command juju add-relation contrail-agent-sriov:juju-info nova-compute-sriov:juju-info
        else
            command juju add-relation contrail-openstack nova-compute
            command juju add-relation contrail-agent:juju-info nova-compute:juju-info
        fi
    fi
    if [[ $ORCHESTRATOR == 'kubernetes' || $ORCHESTRATOR == 'all' ]] ; then
        command juju add-relation contrail-kubernetes-node:cni kubernetes-master:cni
        command juju add-relation contrail-kubernetes-node:cni kubernetes-worker:cni
        command juju add-relation contrail-kubernetes-master:kube-api-endpoint kubernetes-master:kube-api-endpoint
        command juju add-relation contrail-agent:juju-info kubernetes-worker:juju-info
    fi
    if [[ $ORCHESTRATOR == 'all' ]] ; then
        command juju add-relation kubernetes-master keystone
        command juju add-relation kubernetes-master contrail-agent
        setup_keystone_auth
   fi

    # TODO: remove this hack at all!!!
    JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
    for machine in $JUJU_MACHINES ; do
        # fix /etc/hosts
        if [ $CLOUD == 'aws' ] ; then
            # we need to wait while machine is up for aws deployment
            wait_cmd_success "command juju ssh $machine 'uname -a'"
        fi
        juju_node_ip=`$(which juju) ssh $machine "hostname -i" 2>/dev/null | tr -d '\r' | cut -f 1 -d ' '`
        juju_node_hostname=`$(which juju) ssh $machine "hostname -f" 2>/dev/null | tr -d '\r' | cut -f 1 -d ' '`
        command juju ssh $machine "sudo bash -c 'echo $juju_node_ip $juju_node_hostname >> /etc/hosts'" 2>/dev/null
    done

    # show results
    TF_UI_IP=${TF_UI_IP:-"$NODE_IP"}
    echo "Tungsten Fabric Web UI will be available at https://$TF_UI_IP:8143"
    echo "Use admin/password to log in (use 'admin_domain' as domain in case of OpenStack deployment)"
    echo "Or source stackrc for CLI tools after successful deployment"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    local valid_statuses='executing|waiting'
    if is_after_stage 'tf' ; then
        valid_statuses='executing|blocked|waiting'
    fi
    local status=`$(which juju) status`
    if [[ $status =~ "error" ]]; then
        echo "ERROR: Deployment has failed because juju state is error"
        echo "$status"
        exit 1
    fi
    [[ ! $(echo "$status" | egrep $valid_statuses) ]]
}

function collect_deployment_env() {
    if ! is_after_stage 'wait' ; then
        # deployment environment for juju is needed after wait stage only
        return 0
    fi
    echo "INFO: collect deployment env"
    if [[ $ORCHESTRATOR == 'openstack' || "$ORCHESTRATOR" == "all" ]] ; then
        DEPLOYMENT_ENV['AUTH_URL']="http://$(command juju status keystone --format tabular | grep 'keystone/' | head -1 | awk '{print $5}'):5000/v3"
        echo "INFO: auth_url=$DEPLOYMENT_ENV['AUTH_URL']"
    fi

    export CONTROLLER_NODES="`get_juju_unit_ips contrail-controller`"
    echo "INFO: controller_nodes: $CONTROLLER_NODES"

    export AGENT_NODES="`get_juju_unit_ips contrail-agent`"
    echo "INFO: agent_nodes: $AGENT_NODES"

    DEPLOYMENT_ENV['CONTROL_NODES']="$(command juju run --unit contrail-controller/leader 'cat /etc/contrail/common_config.env' | grep CONTROL_NODES | cut -d '=' -f 2)"

    if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
        echo "INFO: SSL is enabled. collecting certs"
        # in case of Juju several files can be placed inside subfolders (for different charms). take any.
        DEPLOYMENT_ENV['SSL_KEY']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep server-privkey.pem | head -1 | xargs sudo base64 -w 0')"
        DEPLOYMENT_ENV['SSL_CERT']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep server.pem | head -1 | xargs sudo base64 -w 0')"
        DEPLOYMENT_ENV['SSL_CACERT']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep ca-cert.pem | head -1 | xargs sudo base64 -w 0')"
    fi

    # NOTE: create stackrc locally to be able to run openstack commands
    create_stackrc
}

function collect_logs() {
    collect_logs_from_machines
    collect_juju_status
}

run_stages $STAGE
