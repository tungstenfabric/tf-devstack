#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ -z ${SUDO_USER+x} ]]; then
   echo "Stop. Please run this scripts with sudo"
   exit 1
fi

if [ -f /home/$SUDO_USER/rhosp-environment.sh ]; then
   source /home/$SUDO_USER/rhosp-environment.sh
else
   echo "File /home/$SUDO_USER/rhosp-environment.sh not found"
   exit
fi
if [ ! -f /home/$SUDO_USER/create_docker_config.sh ]; then
   echo "File /home/$SUDO_USER/create_docker_config.sh not found"
   exit
fi

if [ ! -f /home/$SUDO_USER/rhel_provisioning.sh ]; then
   echo "File /home/$SUDO_USER/rhel_provisioning.sh not found"
   exit
fi

function is_registry_insecure() {
    local registry=`echo $1 | sed 's|^.*://||' | cut -d '/' -f 1`
    if  curl -s -I --connect-timeout 60 http://$registry/v2/ ; then
        return 0
    fi
    return 1
}

#Removing default gateway if it's defined
check_gateway=$(ip route list | grep -c default)
if (( $check_gateway > 0 )); then
   ip route delete default
   echo default gateway deleted
fi

ip route add default via ${prov_ip} dev eth0
sed -i '/nameserver/d'  /etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf

/home/$SUDO_USER/rhel_provisioning.sh
CONTAINER_REGISTRY="" CONFIGURE_DOCKER_LIVERESTORE=false /home/$SUDO_USER/create_docker_config.sh

insecure_registries="--insecure-registry ${prov_ip}:8787"
if [ -n "$CONTAINER_REGISTRY" ] && is_registry_insecure $CONTAINER_REGISTRY ; then
   insecure_registries+=" --insecure-registry $CONTAINER_REGISTRY"
fi
echo INSECURE_REGISTRY="$insecure_registries" >> /etc/sysconfig/docker
systemctl restart docker

#Heat Stack will fail if INSECURE_REGISTRY is presented in the file
#so we delete it and let Heat to append this later
sed -i '$ d' /etc/sysconfig/docker

#Adding current ip and hostname into /etc/hosts
#it's workaround for cassandra UnknownHostException issue on contrail controller
NODE_IP=$(ip addr show dev eth0 | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1)
HOSTNAME=$(hostname)
echo $NODE_IP $HOSTNAME >> /etc/hosts

