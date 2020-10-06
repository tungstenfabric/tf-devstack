#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"
source "$my_dir/providers/common/functions.sh"

init_output_logging

# stages declaration
declare -A STAGES=( \
    ["all"]="build machines undercloud overcloud tf wait logs" \
    ["default"]="machines undercloud overcloud tf wait" \
    ["master"]="build machines undercloud overcloud tf wait" \
    ["platform"]="machines undercloud overcloud" \
)

# default env variables
# max wait in seconds after deployment
export WAIT_TIMEOUT=3600
#PROVIDER = [ kvm | vexx | aws | bmc ]
export PROVIDER=${PROVIDER:-}
[ -n "$PROVIDER" ] || { echo "ERROR: PROVIDER is not set"; exit -1; }
if [[ "$PROVIDER" == "kvm" || "$PROVIDER" == "bmc" ]]; then
    export USE_PREDEPLOYED_NODES=false
    export ENABLE_RHEL_REGISTRATION=${ENABLE_RHEL_REGISTRATION:-'true'}
else
    export USE_PREDEPLOYED_NODES=${USE_PREDEPLOYED_NODES:-true}
    export ENABLE_RHEL_REGISTRATION=${ENABLE_RHEL_REGISTRATION:-'false'}
fi
if [[ "$PROVIDER" == "kvm" ]]; then
    export ENABLE_RHEL_REGISTRATION=${ENABLE_RHEL_REGISTRATION:-'true'}
else
    export ENABLE_RHEL_REGISTRATION=${ENABLE_RHEL_REGISTRATION:-'false'}
fi
#IPMI_PASSOWORD (also it's AdminPassword for TripleO)
export IPMI_PASSWORD=${IPMI_PASSWORD:-'password'}
user=$(whoami)

export ENABLE_NETWORK_ISOLATION=${ENABLE_NETWORK_ISOLATION:-'false'}
export DEPLOY_COMPACT_AIO=${DEPLOY_COMPACT_AIO:-false}
export ORCHESTRATOR=${ORCHESTRATOR:-'openstack'}
export DEPLOYER='rhosp'
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export RHOSP_VERSION=${RHOSP_VERSION:-'rhosp13'}
export SSH_USER=${SSH_USER:-'cloud-user'}
declare -A _osc_registry_default=( ['rhosp13']='registry.access.redhat.com' ['rhosp16']='registry.redhat.io' )
export OPENSTACK_CONTAINER_REGISTRY=${OPENSTACK_CONTAINER_REGISTRY:-${_osc_registry_default[${RHOSP_VERSION}]}}

# empty - disabled
# ipa   - use FreeIPA
export ENABLE_TLS=${ENABLE_TLS:-}
if [[ -n "$ENABLE_TLS" && "$ENABLE_TLS" != 'ipa' ]] ; then
  echo "ERROR: Unsupported TLS configuration $ENABLE_TLS"
  exit 1
fi

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

set_rhosp_version

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=(\
    ['AUTH_URL']=""
)

#Continue deployment stages with environment specific script
source $my_dir/providers/common/functions.sh
source $my_dir/providers/${PROVIDER}/stages.sh

function expand() {
    while read -r line; do
        if [[ "$line" =~ ^export ]]; then
            line="${line//\\/\\\\}"
            line="${line//\"/\\\"}"
            line="${line//\`/\\\`}"
            eval echo "\"$line\""
        else
            echo $line
        fi
    done
}

function prepare_rhosp_env_file() {
    local env_file=$1
    rm -f $env_file
    source $my_dir/config/common.sh
    cat $my_dir/config/common.sh | expand >> $env_file || true
    source $my_dir/config/${RHEL_VERSION}_env.sh
    cat $my_dir/config/${RHEL_VERSION}_env.sh | grep '^export' | expand >> $env_file || true
    source $my_dir/config/${PROVIDER}_env.sh
    cat $my_dir/config/${PROVIDER}_env.sh | grep '^export' | expand >> $env_file || true
    cat <<EOF >> $env_file

export USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES
export PROVIDER="$PROVIDER"
export RHOSP_VERSION="$RHOSP_VERSION"
export OPENSTACK_VERSION="$OPENSTACK_VERSION"
export RHEL_VERSION="$RHEL_VERSION"
export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION
export ENABLE_NETWORK_ISOLATION=$ENABLE_NETWORK_ISOLATION
export DEPLOY_COMPACT_AIO=$DEPLOY_COMPACT_AIO
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG"
export CONTRAIL_DEPLOYER_CONTAINER_TAG="$CONTRAIL_DEPLOYER_CONTAINER_TAG"
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export DEPLOYER_CONTAINER_REGISTRY="$DEPLOYER_CONTAINER_REGISTRY"
export OPENSTACK_CONTAINER_REGISTRY="$OPENSTACK_CONTAINER_REGISTRY"
export IPMI_PASSWORD="$IPMI_PASSWORD"
export ENABLE_TLS=$ENABLE_TLS

EOF

    #Removing duplicate lines
    sudo rm -f /tmp/rhosp-environment.sh
    awk '!a[$0]++' $env_file >/tmp/rhosp-environment.sh
    cat /tmp/rhosp-environment.sh > $env_file
}

prepare_rhosp_env_file "${WORKSPACE}/rhosp-environment.sh"

run_stages $STAGE
