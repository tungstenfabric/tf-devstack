#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"

# stages declaration

declare -A STAGES=( \
    ["all"]="build machines k8s openstack tf wait" \
    ["default"]="machines k8s openstack tf wait" \
    ["master"]="build machines k8s openstack tf wait" \
    ["platform"]="k8s openstack" \
)

# default env variables

export JUJU_REPO=${JUJU_REPO:-$WORKSPACE/contrail-charms}
export ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}  # openstack | kubernetes
export CLOUD=${CLOUD:-local}  # aws | local | manual
export DATA_NETWORK=${DATA_NETWORK:-}

AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-''}
AWS_SECRET_KEY=${AWS_SECRET_KEY:-''}
AWS_REGION=${AWS_REGION:-'us-east-1'}

export UBUNTU_SERIES=${UBUNTU_SERIES:-'bionic'}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export VIRT_TYPE=${VIRT_TYPE:-'qemu'}

export CONTAINER_REGISTRY
export NODE_IP

# stages

function build() {
    "$my_dir/../common/dev_env.sh"
}

function machines() {
    $my_dir/../common/deploy_juju.sh
    if [[ $CLOUD == 'manual' ]] ;then
        if [[ `echo $CONTROLLER_NODES | awk -F ',' '{print NF}'` != 5 ]] ; then
            echo "We support deploy on 5 machines only now."
            echo "You should specify their ip addresses in CONTROLLER_NODES variable."
            exit 0
        fi
        $my_dir/../common/add_juju_machines.sh
    fi
}

function openstack() {
    if [[ "$ORCHESTRATOR" != "openstack" ]]; then
        echo "INFO: Skipping openstack deployment"
    else
        if [[ $CLOUD == 'local' ]] ; then
            echo "The deployment of OpenStack on local cloud isn't supported."
            return 0
        fi
        if [[ "$UBUNTU_SERIES" == 'bionic' && "$OPENSTACK_VERSION" == 'queens' ]]; then
            export OPENSTACK_ORIGIN="distro"
        else
            export OPENSTACK_ORIGIN="cloud:$UBUNTU_SERIES-$OPENSTACK_VERSION"
        fi
        if [ $CLOUD == 'aws' ] ; then
            export BUNDLE="$my_dir/files/bundle_openstack_lxd.yaml.tmpl"
        elif [ $CLOUD == 'manual' ] ; then
            export BUNDLE="$my_dir/files/bundle_openstack.yaml.tmpl"
        fi
        $my_dir/../common/deploy_juju_bundle.sh
    fi
}

function k8s() {
    if [[ "$ORCHESTRATOR" != "kubernetes" ]]; then
        echo "INFO: Skipping k8s deployment"
    else
        export BUNDLE="$my_dir/files/bundle_k8s.yaml.tmpl"
        $my_dir/../common/deploy_juju_bundle.sh
    fi
}

function tf() {
    export BUNDLE="$my_dir/files/bundle_contrail.yaml.tmpl"

    # get contrail-charms
    [ -d $JUJU_REPO ] || git clone https://github.com/Juniper/contrail-charms -b R5 $JUJU_REPO
    cd $JUJU_REPO

    $my_dir/../common/deploy_juju_bundle.sh

    if [[ -n $DATA_NETWORK ]] ; then
        juju config contrail-controller data-network=$DATA_NETWORK
    fi

    # add relations between orchestrator and Contrail
    if [[ $ORCHESTRATOR == 'openstack' ]] ; then
        juju add-relation contrail-keystone-auth keystone
        juju add-relation contrail-openstack neutron-api
        juju add-relation contrail-openstack heat
        juju add-relation contrail-openstack nova-compute
        juju add-relation contrail-agent:juju-info nova-compute:juju-info
    elif [[ $ORCHESTRATOR == 'kubernetes' ]] ; then
        juju add-relation contrail-kubernetes-node:cni kubernetes-master:cni
        juju add-relation contrail-kubernetes-node:cni kubernetes-worker:cni
        juju add-relation contrail-kubernetes-master:kube-api-endpoint kubernetes-master:kube-api-endpoint
        juju add-relation contrail-agent:juju-info kubernetes-worker:juju-info
    fi

    JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
    # fix /etc/hosts
    for machine in $JUJU_MACHINES ; do
        if [ $CLOUD == 'aws' ] ; then
            # we need to wait while machine is up for aws deployment
            wait_cmd_success 'juju ssh $machine "uname -a"'
        fi
        juju_node_ip=`juju ssh $machine "hostname -i" | tr -d '\r'`
        juju_node_hostname=`juju ssh $machine "hostname" | tr -d '\r'`
        juju ssh $machine "sudo bash -c 'echo $juju_node_ip $juju_node_hostname >> /etc/hosts'" 2>/dev/null
    done

    # show results

    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    local status=$(juju status)
    if [[ $status =~ "error" ]]; then
        echo "ERROR: Deployment has failed because juju state is error"
        echo "$status"
        exit 1
    fi
    [ ! $(echo $status | egrep 'executing|blocked|waiting') ]
}

run_stages $STAGE
