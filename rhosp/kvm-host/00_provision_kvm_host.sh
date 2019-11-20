#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

apt-get update
apt-get install -y git qemu-kvm iptables-persistent ufw virtinst uuid-runtime \
        qemu-kvm libvirt-clients libvirt-daemon-system bridge-utils virt-manager awscli python-dev hugepages gcc

curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python get-pip.py
pip install virtualbmc


