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


# RHEL Registration
set +x
if [ -f /home/stack/rhel-account.rc ]; then
   source /home/stack/rhel-account.rc
else
   echo "File home/stack/rhel-account.rc not found"
   exit
fi

#set -x
register_opts=''
[ -n "$RHEL_USER" ] && register_opts+=" --username $RHEL_USER"
[ -n "$RHEL_PASSWORD" ] && register_opts+=" --password $RHEL_PASSWORD"

attach_opts='--auto'
if [[ -n "$RHEL_POOL_ID" ]] ; then
   attach_opts="--pool $RHEL_POOL_ID"
fi

#setup default gateway (probably should be done in qcow2 image)
sudo ip route add default via ${prov_ip} dev eth0
sed -i '/nameserver/d'  /etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf


setenforce 0
sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
getenforce
cat /etc/selinux/config
subscription-manager unregister || true
echo subscription-manager register ...
subscription-manager register $register_opts
subscription-manager attach $attach_opts

subscription-manager repos --disable=*
subscription-manager repos --enable=rhel-7-server-rpms --enable=rhel-7-server-extras-rpms --enable=rhel-7-server-rh-common-rpms --enable=rhel-ha-for-rhel-7-server-rpms --enable=rhel-7-server-openstack-13-rpms
yum update -y

yum install -y  ntp wget yum-utils vim python-heat-agent*

chkconfig ntpd on
service ntpd start

# install pip for future run of OS checks
curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
sudo python get-pip.py
sudo pip install -q virtualenv docker

sudo echo INSECURE_REGISTRY="--insecure-registry ${prov_ip}:8787" >> /etc/sysconfig/docker
sudo systemctl restart docker

#Heat Stack will fail if INSECURE_REGISTRY is presented in the file
#so we delete it and let heat append this later
sudo sed -i '$ d' /etc/sysconfig/docker


