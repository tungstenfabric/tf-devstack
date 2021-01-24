#!/bin/bash

[[ "$DEBUG" == true ]] && set -x

set -o errexit

if [[ $(whoami) == root ]]; then
  echo "ERROR: Please run script as non-root user"
  exit 1
fi

# working environment
export WORKSPACE=${WORKSPACE:-$(pwd)}
TF_CONFIG_DIR=${TF_CONFIG_DIR:-"${HOME}/.tf"}
TF_DEVENV_PROFILE="${TF_CONFIG_DIR}/dev.env"
TF_STACK_PROFILE="${TF_CONFIG_DIR}/stack.env"
TF_STAGES_DIR="${TF_CONFIG_DIR}/.stages"

# determined variables
export DISTRO=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
export PHYS_INT=`ip route get 1 | grep -o 'dev.*' | awk '{print($2)}'`
export NODE_IP=`ip addr show dev $PHYS_INT | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1`
export NODE_CIDR=`ip r | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+ dev $PHYS_INT " | awk '{print $1}'`
export SSH_USER=${SSH_USER:-${IMAGE_SSH_USER:-$(whoami)}}
# defaults

# run build contrail
DEV_ENV=${DEV_ENV:-false}

# defaults for stack deployment
# If not set will be default 'tungstenfabric'
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-}
export DEPLOYER_CONTAINER_REGISTRY=${DEPLOYER_CONTAINER_REGISTRY:-$CONTAINER_REGISTRY}
# If not set will be default 'latest'
#(it is set in load_tf_devenv_profile)
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-}
export CONTRAIL_DEPLOYER_CONTAINER_TAG=${CONTRAIL_DEPLOYER_CONTAINER_TAG:-$CONTRAIL_CONTAINER_TAG}

CONTROLLER_NODES="${CONTROLLER_NODES:-$NODE_IP}"
CONTROL_NODES="${CONTROL_NODES:-$CONTROLLER_NODES}"
export CONTROLLER_NODES="$(echo $CONTROLLER_NODES | tr ',' ' ')"
export CONTROL_NODES="$(echo $CONTROL_NODES | tr ',' ' ')"
AGENT_NODES="${AGENT_NODES:-$NODE_IP}"
export AGENT_NODES="$(echo $AGENT_NODES | tr ',' ' ')"

export TF_LOG_DIR=${TF_LOG_DIR:-${TF_CONFIG_DIR}/logs}
export SSL_ENABLE=${SSL_ENABLE:-false}
export LEGACY_ANALYTICS_ENABLE=${LEGACY_ANALYTICS_ENABLE:-true}
export SSH_OPTIONS=${SSH_OPTIONS:-"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"}
