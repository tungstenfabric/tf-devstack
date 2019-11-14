#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi


# create stack user
if ! grep -q 'stack' /etc/passwd ; then
  useradd -m stack -s /bin/bash
else
  echo User stack is already exist
fi
echo "stack:password" | chpasswd
echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
chmod 0440 /etc/sudoers.d/stack

cp *.rc *.template 02_deploy_as_stack.sh /home/stack/

#yum -y install python-tripleoclient python-rdomanager-oscplugin  openstack-utils
yum -y install python-tripleoclient python-rdomanager-oscplugin


yum-config-manager --enable rhelosp-rhel-7-server-opt
yum install -y rhosp-director-images

# install pip for future run of OS checks
#curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
#python get-pip.py
#pip install -q virtualenv


