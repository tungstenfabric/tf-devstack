#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
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


setenforce 0
sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
getenforce
cat /etc/selinux/config
subscription-manager unregister || true
echo subscription-manager register ...
subscription-manager register $register_opts
subscription-manager attach $attach_opts

subscription-manager repos --disable=*
subscription-manager repos --enable=rhel-7-server-rpms --enable=rhel-7-server-extras-rpms --enable=rhel-7-server-rh-common-rpms \
     --enable=rhel-ha-for-rhel-7-server-rpms --enable=rhel-7-server-openstack-13-rpms --enable=rhel-7-server-rhceph-3-tools-rpms
yum update -y

yum install -y  ntp wget yum-utils screen mc deltarpm createrepo bind-utils sshpass \
                     gcc make python-devel yum-plugin-priorities sshpass libguestfs-tools libvirt-client

chkconfig ntpd on
service ntpd start

yum install -y vim
