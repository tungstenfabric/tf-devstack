#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"


# default env variables
export JUJU_REPO=${JUJU_REPO:-$WORKSPACE/contrail-charms}
export ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}  # openstack | kubernetes
export CLOUD=${CLOUD:-local}  # aws | local

AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-''}
AWS_SECRET_KEY=${AWS_SECRET_KEY:-''}
AWS_REGION=${AWS_REGION:-'us-east-1'}

SKIP_JUJU_BOOTSTRAP=${SKIP_JUJU_BOOTSTRAP:-false}
SKIP_JUJU_ADD_MACHINES=${SKIP_JUJU_ADD_MACHINES:-false}
SKIP_ORCHESTRATOR_DEPLOYMENT=${SKIP_ORCHESTRATOR_DEPLOYMENT:-false}
SKIP_CONTRAIL_DEPLOYMENT=${SKIP_CONTRAIL_DEPLOYMENT:-false}

export UBUNTU_SERIES=${UBUNTU_SERIES:-'bionic'}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export VIRT_TYPE=${VIRT_TYPE:-'qemu'}

export CONTAINER_REGISTRY
export NODE_IP

# build step

# install juju
if [ $SKIP_JUJU_BOOTSTRAP == false ]; then
    echo "Installing JuJu, setup and bootstrap JuJu controller"
    $my_dir/../common/deploy_juju.sh
fi

# build step

if [[ "$DEV_ENV" == true ]]; then
    "$my_dir/../common/dev_env.sh"
fi

# add-machines to juju
if [[ $SKIP_JUJU_ADD_MACHINES == false && $CLOUD != 'local' ]]; then
    echo "Add machines to JuJu"
    export NUMBER_OF_MACHINES_TO_DEPLOY=2
    $my_dir/../common/add_juju_machines.sh

    # fix lxd profile to let docker containers run on lxd
    if [[ $ORCHESTRATOR == 'openstack' ]] ; then
        JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
        for machine in $JUJU_MACHINES ; do
            juju scp "$my_dir/files/lxd-default.yaml" $machine:lxd-default.yaml 2>/dev/null
            juju ssh $machine "cat ./lxd-default.yaml | sudo lxc profile edit default"
        done
    fi
fi

# deploy orchestrator
if [ $SKIP_ORCHESTRATOR_DEPLOYMENT == false ]; then
    if [[ $ORCHESTRATOR == 'openstack' && $CLOUD == 'local' ]] ; then
        echo "The deployment of OpenStack on local cloud isn't supported."
        exit 0
    fi
    echo "Deploy ${ORCHESTRATOR^}"
    if [[ $ORCHESTRATOR == 'openstack' ]] ; then
        if [[ "$UBUNTU_SERIES" == 'bionic' && "$OPENSTACK_VERSION" == 'queens' ]]; then
            export OPENSTACK_ORIGIN="distro"
        else
            export OPENSTACK_ORIGIN="cloud:$UBUNTU_SERIES-$OPENSTACK_VERSION"
        fi
        export BUNDLE="$my_dir/files/bundle_openstack.yaml.tmpl"
    elif [[ $ORCHESTRATOR == 'kubernetes' ]] ; then
        export BUNDLE="$my_dir/files/bundle_k8s.yaml.tmpl"
    fi
    $my_dir/../common/deploy_juju_bundle.sh
fi

# deploy contrail
if [ $SKIP_CONTRAIL_DEPLOYMENT == false ]; then
    echo "Deploy Contrail"
    export BUNDLE="$my_dir/files/bundle_contrail.yaml.tmpl"

    # get contrail-charms
    [ -d $JUJU_REPO ] || git clone https://github.com/Juniper/contrail-charms -b R5 $JUJU_REPO
    cd $JUJU_REPO

    $my_dir/../common/deploy_juju_bundle.sh

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
        juju_node_ip=`juju ssh $machine "hostname -i" | tr -d '\r'`
        juju_node_hostname=`juju ssh $machine "hostname" | tr -d '\r'`
        juju ssh $machine "sudo bash -c 'echo $juju_node_ip $juju_node_hostname >> /etc/hosts'" 2>/dev/null
    done
fi

safe_tf_stack_profile

# show results
echo "Deployment scripts are finished"
echo "Now you can monitor when contrail becomes available with:"
echo "juju status"
if [ $SKIP_CONTRAIL_DEPLOYMENT == false ]; then
    echo "All applications and units should become active, before you can use Contrail"
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
fi
