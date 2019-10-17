#!/bin/bash

set -o errexit

# determined variables

DISTRO=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
PHYS_INT=`ip route get 1 | grep -o 'dev.*' | awk '{print($2)}'`
NODE_IP=`ip addr show dev $PHYS_INT | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1`

# defaults

DEV_ENV=${DEV_ENV:-false}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-opencontrailnightly}
CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-master-latest}
CONTROLLER_NODES=${CONTROLLER_NODES:-$NODE_IP}
AGENT_NODES=${AGENT_NODES:-$NODE_IP}
