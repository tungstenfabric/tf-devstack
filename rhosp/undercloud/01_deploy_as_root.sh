#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi



#yum -y install python-tripleoclient python-rdomanager-oscplugin  openstack-utils
yum -y install python-tripleoclient python-rdomanager-oscplugin iproute


yum-config-manager --enable rhelosp-rhel-7-server-opt
yum install -y rhosp-director-images

# install pip for future run of OS checks
#curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
#python get-pip.py
#pip install -q virtualenv

#Creating user stack
