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
if [ -z "$default_dev" ] ; then
   echo "ERROR: undercloud node is not reachable from overcloud via prov network"
   exit 1
fi
ip route replace default via ${prov_ip} dev $default_dev
echo GATEWAYDEV=$default_dev >> /etc/sysconfig/network
echo GATEWAY=$prov_ip >> /etc/sysconfig/network

sed -i '/nameserver/d'  /etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf

./rhel_provisioning.sh
CONTAINER_REGISTRY="" CONFIGURE_DOCKER_LIVERESTORE=false ./create_docker_config.sh
insecure_registries=$(cat /etc/sysconfig/docker | awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' | tr -d '"')
if ! echo "$insecure_registries" | grep -q "${prov_ip}:8787" ; then
   insecure_registries+=" --insecure-registry ${prov_ip}:8787"
   sed -i '/^INSECURE_REGISTRY/d' /etc/sysconfig/docker
   echo "INSECURE_REGISTRY=\"$insecure_registries\"" | tee -a /etc/sysconfig/docker
fi

if ! systemctl restart docker ; then
   systemctl status docker.service
   journalctl -xe
   exit 1
fi
