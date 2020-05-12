#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

init_output_logging

# stages declaration
declare -A STAGES=( \
    ["all"]="build machines undercloud overcloud tf wait logs" \
    ["default"]="machines undercloud overcloud tf wait" \
    ["master"]="build machines undercloud overcloud tf wait" \
    ["platform"]="machines undercloud overcloud" \
)

# default env variables
export ENABLE_RHEL_REGISTRATION=${ENABLE_RHEL_REGISTRATION:-'true'}
export DEPLOY_COMPACT_AIO=${DEPLOY_COMPACT_AIO:-false}
export ORCHESTRATOR=${ORCHESTRATOR:-'openstack'}
export DEPLOYER='rhosp'
export RHOSP_VERSION=${RHOSP_VERSION:-'rhosp13'}
export SSH_USER=${SSH_USER:-'cloud-user'}

if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
    if [[ -z ${RHEL_USER+x} ]]; then
        echo "There is no Red Hat Credentials. Please export variable RHEL_USER "
        exit 1
    fi

    if [[ -z ${RHEL_PASSWORD+x} ]]; then
        echo "There is no Red Hat Credentials. Please export variable RHEL_PASSWORD "
        exit 1
    fi
fi

if [[ "$RHOSP_VERSION" == "rhosp16" ]]; then
    export RHEL_VERSION='rhel8'
    export OPENSTACK_VERSION='train'
else 
    export RHEL_VERSION='rhel7'
    export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
fi
# max wait in seconds after deployment
export WAIT_TIMEOUT=3600
#PROVIDER = [ kvm | vexx | aws ]
export PROVIDER=${PROVIDER:-'vexx'}
if [[ "$PROVIDER" == "kvm" ]]; then
    export USE_PREDEPLOYED_NODES=false
else
    export USE_PREDEPLOYED_NODES=${USE_PREDEPLOYED_NODES:-true}
fi
#IPMI_PASSOWORD (also it's AdminPassword for TripleO)
export IPMI_PASSWORD=${IPMI_PASSWORD:-'password'}
user=$(whoami)

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=(\
    ['AUTH_URL']=""
)

#Continue deployment stages with environment specific script
source $my_dir/providers/common/functions.sh
source $my_dir/providers/${PROVIDER}/stages.sh


function prepare_rhosp_env_file() {
    ##### Always creating ~/rhosp-environment.sh #####
    rm -f ~/rhosp-environment.sh
    source $my_dir/config/common.sh
    cat $my_dir/config/common.sh | envsubst >>~/rhosp-environment.sh || true
    source $my_dir/config/${RHEL_VERSION}_env.sh
    cat $my_dir/config/${RHEL_VERSION}_env.sh | grep '^export' | envsubst >> ~/rhosp-environment.sh || true
    source $my_dir/config/${PROVIDER}_env.sh
    cat $my_dir/config/${PROVIDER}_env.sh | grep '^export' | envsubst >> ~/rhosp-environment.sh || true
    echo "export USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES" >> ~/rhosp-environment.sh
    echo "export PROVIDER=$PROVIDER" >> ~/rhosp-environment.sh
    echo "export RHOSP_VERSION=$RHOSP_VERSION" >> ~/rhosp-environment.sh
    echo "export OPENSTACK_VERSION=$OPENSTACK_VERSION" >> ~/rhosp-environment.sh
    echo "export RHEL_VERSION=$RHEL_VERSION" >> ~/rhosp-environment.sh
    echo "export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION" >> ~/rhosp-environment.sh 
    echo "export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG" >> ~/rhosp-environment.sh
    echo "export CONTAINER_REGISTRY=$CONTAINER_REGISTRY" >> ~/rhosp-environment.sh 
    echo "export IPMI_PASSWORD=\"$IPMI_PASSWORD\"" >> ~/rhosp-environment.sh

}

#TODO move inside stage to allow overwrite values by dev-env
prepare_rhosp_env_file


run_stages $STAGE
