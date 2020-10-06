
# max wait in seconds after deployment
export WAIT_TIMEOUT=3600

#PROVIDER = [ kvm | vexx | aws | bmc ]
export PROVIDER=${PROVIDER:-}
[ -n "$PROVIDER" ] || { echo "ERROR: PROVIDER is not set"; exit -1; }

export DEPLOYER='rhosp'
export ORCHESTRATOR=${ORCHESTRATOR:-'openstack'}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-"docker.io/tungstenfabric"}

# export OPENSTACK_CONTROLLER_NODES=${OPENSTACK_CONTROLLER_NODES:-}
# export CONTROLLER_NODES=${CONTROLLER_NODES:-1}
# export AGENT_NODES=${AGENT_NODES:-}
# export DPDK_AGENT_NODES=${DPDK_AGENT_NODES:-}
# export SRIOV_AGENT_NODES=${SRIOV_AGENT_NODES:-}

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

declare -A _default_rhosp_version=( ['queens']='rhosp13' ['train']='rhosp16' )
export RHOSP_VERSION=${RHOSP_VERSION:-${_default_rhosp_version[$OPENSTACK_VERSION]}}

declare -A _default_rhel_version=( ['queens']='rhel7' ['train']='rhel8' )
export RHEL_VERSION=${RHEL_VERSION:-${_default_rhel_version[$OPENSTACK_VERSION]}}

declare -A _osc_registry_default=( ['rhosp13']='registry.access.redhat.com' ['rhosp16']='registry.redhat.io' )
export OPENSTACK_CONTAINER_REGISTRY=${OPENSTACK_CONTAINER_REGISTRY:-${_osc_registry_default[${RHOSP_VERSION}]}}

export IPMI_USER=${IPMI_USER:-'ADMIN'}
export IPMI_PASSWORD=${IPMI_PASSWORD:-'ADMIN'}

export undercloud_local_interface=${undercloud_local_interface:-'eth1'}

export ssh_opts='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no'
export SSH_EXTRA_OPTIONS=${SSH_EXTRA_OPTIONS:-}

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
