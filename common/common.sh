#!/bin/bash

[[ "$DEBUG" == true ]] && set -x

set -o errexit

# working environment
WORKSPACE=${WORKSPACE:-$(pwd)}
TF_CONFIG_DIR=${TF_CONFIG_DIR:-"${HOME}/.tf"}
TF_DEVENV_PROFILE="${TF_CONFIG_DIR}/dev.env"
TF_STACK_PROFILE="${TF_CONFIG_DIR}/stack.env"
TF_STAGES_DIR="${TF_CONFIG_DIR}/.stages"

# determined variables
DISTRO=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
PHYS_INT=`ip route get 1 | grep -o 'dev.*' | awk '{print($2)}'`
NODE_IP=`ip addr show dev $PHYS_INT | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1`

# defaults

# run build contrail
DEV_ENV=${DEV_ENV:-false}

# defaults for stack deployment
# If not set will be default 'tungstenfabric'
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-}
# If not set will be default 'latest'
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-}
export CONTROLLER_NODES=${CONTROLLER_NODES:-$NODE_IP}
export AGENT_NODES=${AGENT_NODES:-$NODE_IP}

if [[ "$(whoami)" == "root" ]]; then
  echo Please run script as non-root user
  exit 1
fi

