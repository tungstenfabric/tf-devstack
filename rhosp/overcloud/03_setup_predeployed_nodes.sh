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
if [[ -z "$default_dev" || 'lo' == "$default_dev" ]] ; then
   echo "ERROR: undercloud node is not reachable from overcloud via prov network"
   exit 1
fi
ip route replace default via ${prov_ip} dev $default_dev
cfg_file="/etc/sysconfig/network-scripts/ifcfg-$default_dev"
sed -i '/^GATEWAY[ ]*=/d' $cfg_file
echo "GATEWAY=${prov_ip}" >> $cfg_file

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

# to avoid slow ssh connect if dns is not available
sed -i 's/.*UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
service sshd reload
