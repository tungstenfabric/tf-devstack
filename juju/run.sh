#!/bin/bash

# TODO:
# support openstack train for MAAS deployment
# support ironic in MAAS deployment

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
    ["platform"]="juju machines k8s openstack" \
)

export PATH=$PATH:/snap/bin

# default env variables
export DEPLOYER='juju'
export CLOUD=${CLOUD:-manual}  # aws | maas | manual
default_timeout=3000
if [[ "$CLOUD" == 'maas' ]]; then default_timeout=9000 ; fi
export WAIT_TIMEOUT=${WAIT_TIMEOUT:-$default_timeout}

export JUJU_REPO=${JUJU_REPO:-$WORKSPACE/tf-charms}
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
export ENABLE_NAGIOS=${ENABLE_NAGIOS:-'false'}
export ENABLE_IRONIC=${ENABLE_IRONIC:-'false'}

AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-''}
AWS_SECRET_KEY=${AWS_SECRET_KEY:-''}
AWS_REGION=${AWS_REGION:-'us-east-1'}

MAAS_ENDPOINT=${MAAS_ENDPOINT:-''}
MAAS_API_KEY=${MAAS_API_KEY:-''}

export SRIOV_PHYSICAL_NETWORK=${SRIOV_PHYSICAL_NETWORK:-'physnet1'}
export SRIOV_PHYSICAL_INTERFACE=${SRIOV_PHYSICAL_INTERFACE:-'ens2f1'}
export SRIOV_VF=${SRIOV_VF:-4}

source /etc/lsb-release
export UBUNTU_SERIES=${UBUNTU_SERIES:-${DISTRIB_CODENAME}}
declare -A default_openstacks=( ["bionic"]="train" ["focal"]="ussuri" )
default_openstack=${default_openstacks[$UBUNTU_SERIES]}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-$default_openstack}
export VIRT_TYPE=${VIRT_TYPE:-'qemu'}

export CONTAINER_REGISTRY
export NODE_IP
export VIRTUAL_IPS
export CONTAINER_RUNTIME

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
    if [[ $ORCHESTRATOR == 'hybrid' ]] ; then
        # in case k8s is deploying before lxd container creating,
        # lxd have wrong parent in config and can't get IP address
        # to prevent it we starts lxd before
        command juju deploy cs:$UBUNTU_SERIES/ubuntu --to lxd:0
    fi

    configure_mtu
}

function openstack() {
    if [[ "$ORCHESTRATOR" != "openstack" && $ORCHESTRATOR != 'hybrid' ]]; then
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
        if [[ ${ENABLE_IRONIC^^} == 'TRUE' ]]; then
            echo "ERROR: Ironic is not supported yet in MAAS env. Please disable it with 'export ENABLE_IRONIC=false'."
            exit 1
        fi
        IPS_COUNT=`echo $VIRTUAL_IPS | wc -w`
        if [[ "$IPS_COUNT" != 9 ]] && [[ "$IPS_COUNT" != 1 ]] ; then
            echo "ERROR: We support deploy with 9 virtual ip addresses only now."
            echo "You must specify the first address in the range or all seven IP in VIRTUAL_IPS variable."
            exit 1
        fi
        if [[ "$IPS_COUNT" = 1 ]] ; then
            export VIRTUAL_IPS=$(prips $(netmask ${VIRTUAL_IPS} | tr -d "[:space:]") | \
                grep -P "^${VIRTUAL_IPS%/*}$"  -A7 | tr '\n' ' ')
        fi
        export BUNDLE="$my_dir/files/bundle_openstack_maas_ha.yaml.tmpl"
    fi
    $my_dir/../common/deploy_juju_bundle.sh

    wait_cmd_success is_ready 10 $((WAIT_TIMEOUT/10))

    if [[ ${ENABLE_IRONIC,,} == 'true' && ($ORCHESTRATOR == 'openstack' || $ORCHESTRATOR == 'hybrid') ]] ; then
        # this should be done after openstak deploy
        command juju run-action --wait ironic-conductor/leader set-temp-url-secret
    fi
}

function k8s() {
    if [[ "$ORCHESTRATOR" != "kubernetes" && $ORCHESTRATOR != 'hybrid' ]]; then
        echo "INFO: Skipping k8s deployment"
        return
    fi
    if [[ "${CONTRAIL_CONTAINER_TAG,,}" =~ 'r2011' || "${CONTRAIL_CONTAINER_TAG,,}" =~ 'r1912' ]] ; then
        export K8S_VERSION="v1.18"
        echo "INFO: use k8s $K8S_VERSION for branches r2011 and r1912"
    fi
    export BUNDLE="$my_dir/files/bundle_k8s.yaml.tmpl"
    $my_dir/../common/deploy_juju_bundle.sh

    wait_cmd_success is_ready 10 $((WAIT_TIMEOUT/10))
}

function tf() {
    sync_time $SSH_USER $(get_juju_unit_ips ubuntu)
    if [ $CLOUD == 'maas' ] ; then
        TF_UI_IP=$(command juju show-machine 0 --format tabular | grep '^0\s' | awk '{print $3}')
    fi
    export BUNDLE="$my_dir/files/bundle_tf.yaml.tmpl"
    if [[ $ORCHESTRATOR == 'openstack' || $ORCHESTRATOR == 'hybrid' ]] ; then
        export KUBERNETES_CLUSTER_DOMAIN="admin_domain"
    fi

    # get tf-charms
    if [[ ! -d $JUJU_REPO ]] ; then
        if ! fetch_deployer_no_docker $tf_charms_image $JUJU_REPO ; then
            echo "WARNING: failed to fetch $tf_charms_image, use github"
            git clone https://github.com/tungstenfabric/tf-charms $JUJU_REPO
        fi
        if [[ -n "$CONTRAIL_DEPLOYER_BRANCH" ]] ; then
            pushd $JUJU_REPO
            git checkout $CONTRAIL_DEPLOYER_BRANCH
            popd
        fi
    fi

    cd $JUJU_REPO

    # do not retry hooks during tf deployment
    command juju model-config automatically-retry-hooks=false

    $my_dir/../common/deploy_juju_bundle.sh

    # add relations between orchestrator and TF
    if [[ $ORCHESTRATOR == 'openstack' || $ORCHESTRATOR == 'hybrid' ]] ; then
        command juju add-relation tf-keystone-auth keystone
        command juju add-relation tf-openstack neutron-api
        command juju add-relation tf-openstack heat
        if [[ ${ENABLE_DPDK_SRIOV,,} == 'true' ]] ; then
            command juju add-relation tf-openstack nova-compute-dpdk
            command juju add-relation tf-agent-dpdk:juju-info nova-compute-dpdk:juju-info
            command juju add-relation tf-openstack nova-compute-sriov
            command juju add-relation tf-agent-sriov:juju-info nova-compute-sriov:juju-info
        else
            command juju add-relation tf-openstack nova-compute
            command juju add-relation tf-agent:juju-info nova-compute:juju-info
        fi
        if [[ ${ENABLE_NAGIOS,,} == 'true' ]] ; then
            # add nrpe relation to superior of tf-agent
            command juju add-relation nova-compute nrpe
        fi
    fi
    if [[ $ORCHESTRATOR == 'kubernetes' || $ORCHESTRATOR == 'hybrid' ]] ; then
        command juju add-relation tf-kubernetes-node:cni kubernetes-master:cni
        command juju add-relation tf-kubernetes-node:cni kubernetes-worker:cni
        command juju add-relation tf-kubernetes-master:kube-api-endpoint kubernetes-master:kube-api-endpoint
        command juju add-relation tf-agent:juju-info kubernetes-worker:juju-info
        if [[ ${ENABLE_NAGIOS,,} == 'true' ]] ; then
            # add nrpe relation to superior of tf-agent and contail-kubernetes-master
            command juju add-relation kubernetes-master nrpe
            command juju add-relation kubernetes-worker nrpe
        fi
    fi
    if [[ $ORCHESTRATOR == 'hybrid' ]] ; then
        command juju add-relation kubernetes-master keystone
        command juju add-relation kubernetes-master tf-agent
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
        if [[ $CONTRAIL_CONTAINER_TAG =~ "1912" ]]; then
            # R1912 release doesn't support hugepages for vrouter and thus vrouter-agent requires some big blocks of free memory
            # TODO: apply this only on agents
            echo "INFO: apply memory setting for vrouter-agent"
            command juju ssh $machine "sudo bash -c 'echo 6291456 > /proc/sys/vm/min_free_kbytes'" 2>/dev/null
        fi
    done

    # show results
    TF_UI_IP=${TF_UI_IP:-"$NODE_IP"}
    echo "Tungsten Fabric Web UI will be available at https://$TF_UI_IP:8143"
    echo "Use admin/password to log in (use 'admin_domain' as domain in case of OpenStack deployment)"
    echo "Or source stackrc for CLI tools after successful deployment"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    local status=`$(which juju) status`
    if [[ $status =~ "error" ]]; then
        echo "ERROR: Deployment has failed because juju state is error"
        echo "$status"
        exit 1
    fi
    if echo "$status" | egrep 'executing|blocked|waiting' ; then
        return 1
    fi

    # NOTE: kubernetes can't be deployed in AIO configuration properly -
    # worker and master charms have same place for server.crt and thus if
    # worker writes it after master then master can't accept connections
    # to some IP-s/names.
    # If this deployment has kubernetes in AIO and it's server cert is incorrect
    # then script has to override it. just one way was found. it's to add
    # something to extra_sans after deployment
    if ! check_kubernetes_master_cert ; then
        return 1
    fi

    return 0
}

function collect_deployment_env() {
    if ! is_after_stage 'wait' ; then
        # deployment environment for juju is needed after wait stage only
        return 0
    fi

    # NOTE: hack for SRIOV deployments
    # TODO: implement this in charms
    # nova-compute reads configuration once at start but it should re-read it when
    # new VF number is stored in the system. Here just a nova-compute restart for sriov node
    # to let tests pass
    if [[ ${ENABLE_DPDK_SRIOV,,} == 'true' ]]; then
        command juju ssh nova-compute-sriov/0 "sudo systemctl restart nova-compute"
    fi

    echo "INFO: collect deployment env"
    if [[ $ORCHESTRATOR == 'openstack' || "$ORCHESTRATOR" == "hybrid" ]] ; then
        DEPLOYMENT_ENV['AUTH_URL']="http://$(command juju status keystone --format tabular | grep 'keystone/' | head -1 | awk '{print $5}'):$KEYSTONE_SERVICE_PORT/v3"
        echo "INFO: auth_url=$DEPLOYMENT_ENV['AUTH_URL']"
        DEPLOYMENT_ENV['KUBERNETES_CLUSTER_DOMAIN']="admin_domain"
    fi

    export CONTROLLER_NODES="`get_juju_unit_ips tf-controller`"
    echo "INFO: controller_nodes: $CONTROLLER_NODES"

    export AGENT_NODES="`get_juju_unit_ips tf-agent.*`"
    echo "INFO: agent_nodes: $AGENT_NODES"

    DEPLOYMENT_ENV['CONTROL_NODES']="$(command juju run --unit tf-controller/leader 'cat /etc/contrail/common_config.env' | grep CONTROL_NODES | cut -d '=' -f 2)"
    DEPLOYMENT_ENV['DPDK_AGENT_NODES']=$(get_juju_unit_ips tf-agent-dpdk)
    sriov_agent_nodes=$(get_juju_unit_ips tf-agent-sriov)
    for node in $sriov_agent_nodes; do
        [ -z "${DEPLOYMENT_ENV['SRIOV_CONFIGURATION']}" ] || DEPLOYMENT_ENV['SRIOV_CONFIGURATION']+=';'
        DEPLOYMENT_ENV['SRIOV_CONFIGURATION']+="$node:$SRIOV_PHYSICAL_NETWORK:$SRIOV_PHYSICAL_INTERFACE:$SRIOV_VF";
    done
    if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
        echo "INFO: SSL is enabled. collecting certs"
        # in case of Juju several files can be placed inside subfolders (for different charms). take any.
        DEPLOYMENT_ENV['SSL_KEY']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep server-privkey.pem | head -1 | xargs sudo base64 -w 0')"
        DEPLOYMENT_ENV['SSL_CERT']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep server.pem | head -1 | xargs sudo base64 -w 0')"
        DEPLOYMENT_ENV['SSL_CACERT']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep ca-cert.pem | head -1 | xargs sudo base64 -w 0')"
    fi

    DEPLOYMENT_ENV['ENABLE_NAGIOS']="${ENABLE_NAGIOS}"

    # NOTE: create stackrc locally to be able to run openstack commands
    create_stackrc
}

function collect_logs() {
    collect_logs_from_machines
    collect_juju_status
}

run_stages $STAGE
