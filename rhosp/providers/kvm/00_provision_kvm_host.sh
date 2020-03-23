#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git qemu-kvm iptables-persistent ufw virtinst uuid-runtime \
        qemu-kvm libvirt-clients libguestfs-tools libvirt-daemon-system bridge-utils virt-manager awscli python-dev hugepages gcc

curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python get-pip.py
#virtualbmc==2.0.0 doesn't do node introspection in tripleo. 1.5.0 works well!
pip install virtualbmc==1.5.0 configparser

ufw allow ssh
ufw allow from 192.0.0.0/8 to any
ufw allow from 10.0.0.0/8 to any
ufw allow from 172.0.0.0/8 to any
ufw enable

