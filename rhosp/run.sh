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


declare -A _default_predeployed_mode=( ['vexx']='true' ['kvm']='false' ['bmc']='false' )
export USE_PREDEPLOYED_NODES=${USE_PREDEPLOYED_NODES:-${_default_predeployed_mode[$PROVIDER]}}

declare -A _default_rhel_registration=( ['vexx']='false' ['kvm']='true' ['bmc']='false' )
export ENABLE_RHEL_REGISTRATION=${ENABLE_RHEL_REGISTRATION:-${_default_rhel_registration[$PROVIDER]}}

declare -A _default_net_isolation=( ['vexx']='false' ['kvm']='false' ['bmc']='true' )
export ENABLE_NETWORK_ISOLATION=${ENABLE_NETWORK_ISOLATION:-${_default_net_isolation[$PROVIDER]}}

declare -A _default_aio=( ['vexx']='true' ['kvm']='false' ['bmc']='false' )
export DEPLOY_COMPACT_AIO=${DEPLOY_COMPACT_AIO:-${_default_aio[$PROVIDER]}}

declare -A _default_ssh_user=( ['vexx']='cloud-user' ['kvm']='stack' ['bmc']="$(whoami)" )
export SSH_USER=${SSH_USER:-${_default_ssh_user[$PROVIDER]}}

#IPMI_PASSOWORD (also it's AdminPassword for TripleO)
export IPMI_PASSWORD=${IPMI_PASSWORD:-'password'}

export ORCHESTRATOR=${ORCHESTRATOR:-'openstack'}
export DEPLOYER='rhosp'
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export RHOSP_VERSION=${RHOSP_VERSION:-'rhosp13'}


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
source $my_dir/providers/${PROVIDER}/stages.sh

run_stages $STAGE
