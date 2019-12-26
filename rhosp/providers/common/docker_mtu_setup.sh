#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [ -f /home/stack/env.sh ]; then
   source /home/stack/env.sh
else
   echo "File /home/stack/env.sh not found"
   exit
fi


#Auto-detect physnet MTU for cloud environments
default_iface=`ip route get 1 | grep -o "dev.*" | awk '{print $2}'`
default_iface_mtu=`ip link show $default_iface | grep -o "mtu.*" | awk '{print $2}'`

if (( ${default_iface_mtu} < 1500 )); then
  echo "{ \"mtu\": ${default_iface_mtu}, \"debug\":false }" > /etc/docker/daemon.json
fi

systemctl restart docker


