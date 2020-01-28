#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ -z ${RHEL_USER+x} && -z ${RHEL_PASSWORD+x} && -z ${RHEL_POOL_ID+x} ]]; then
   echo "Stop. Please define variables RHEL_USER, RHEL_PASSWORD and RHEL_POOL_ID"
   exit 1
fi

set +x
register_opts=''
[ -n "$RHEL_USER" ] && register_opts+=" --username $RHEL_USER"
[ -n "$RHEL_PASSWORD" ] && register_opts+=" --password $RHEL_PASSWORD"

attach_opts='--auto'
if [[ -n "$RHEL_POOL_ID" ]] ; then
   attach_opts="--pool $RHEL_POOL_ID"
fi

cd
setenforce 0
sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
getenforce
cat /etc/selinux/config
subscription-manager unregister || true
echo subscription-manager register ...
subscription-manager register $register_opts
subscription-manager attach $attach_opts

set -x

subscription-manager repos --disable=*
subscription-manager repos --enable=rhel-7-server-rpms --enable=rhel-7-server-extras-rpms --enable=rhel-7-server-rh-common-rpms --enable=rhel-ha-for-rhel-7-server-rpms --enable=rhel-7-server-openstack-13-rpms
yum update -y

yum install -y  ntp wget yum-utils vim iproute net-tools python-heat-agent*

chkconfig ntpd on
service ntpd start

# install pip for future run of OS checks
curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
python get-pip.py
pip install -q virtualenv docker

