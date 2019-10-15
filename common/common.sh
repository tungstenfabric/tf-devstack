#!/bin/bash

set -o errexit

phys_int=`ip route get 1 | grep -o 'dev.*' | awk '{print($2)}'`

# constants

DEPLOYER_IMAGE=contrail-k8s-manifests
DEPLOYER_NAME=contrail-container-buider
DEPLOYER_DIR=contrail-container-builder

# determined variables

DISTRO=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
NODE_IP=`ip addr show dev $phys_int | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1`
