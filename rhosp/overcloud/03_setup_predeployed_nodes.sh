#!/bin/bash -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ -z ${SUDO_USER+x} ]]; then
   echo "Stop. Please run this scripts with sudo"
   exit 1
fi

cd /home/$SUDO_USER

source ./rhosp-environment.sh

#Set default gateway to undercloud
default_dev=$(ip route get $prov_ip | grep -o "dev.*" | awk '{print $2}')
ip route change default via ${prov_ip} dev $default_dev
sed -i '/nameserver/d'  /etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf

./rhel_provisioning.sh
CONTAINER_REGISTRY="" CONFIGURE_DOCKER_LIVERESTORE=false ./create_docker_config.sh
if ! systemctl restart docker ; then
   systemctl status docker.service
   journalctl -xe
   exit 1
fi
