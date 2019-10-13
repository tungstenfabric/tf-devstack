#!/bin/bash

set -o errexit

distro=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
PHYSICAL_INTERFACE=`ip route get 1 | grep -o 'dev.*' | awk '{print($2)}'`
NODE_IP=`ip addr show dev $PHYSICAL_INTERFACE | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1`
