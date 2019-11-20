#!/bin/sh


export poolname="rdimages"

# define undercloud virtual machine's names
export undercloud_prefix="undercloud"
export undercloud_vmname="rhosp13-undercloud"

export BASE_IMAGE="/home/ggalkin/rhel_7.7.qcow2"

#define virtual machine's volumes

export undercloud_vm_volume="$undercloud_prefix.qcow2"

# network names and settings
export BRIDGE_NAME_MGMT=${BRIDGE_NAME_MGMT:-"mgmt"}
export BRIDGE_NAME_PROV=${BRIDGE_NAME_PROV:-"prov"}
export NET_NAME_MGMT=${NET_NAME_MGMT:-${BRIDGE_NAME_MGMT}}
export NET_NAME_PROV=${NET_NAME_PROV:-${BRIDGE_NAME_PROV}}


#IPMI
export IPMI_USER="stack"
export IPMI_PASSWORD="qwe123QWE"

#SSH public key for user stack
export ssh_private_key="/home/ggalkin/.ssh/id_rsa"
export ssh_public_key="/home/ggalkin/.ssh/id_rsa.pub"


# VBMC base port for IPMI management
export VBMC_PORT_BASE=16000

#IP, subnets
export mgmt_subnet="192.168.10"
export mgmt_gateway="${mgmt_subnet}.1"
export mgmt_ip="${mgmt_subnet}.2"

export prov_subnet="192.168.12"
export prov_gateway="${prov_subnet}.1"
export prov_ip="${prov_subnet}.2"

export fixed_vip="${prov_subnet}.200"
export fixed_controller_ip="${prov_subnet}.211"

export CONTRAIL_VERSION="5.1"

#VM nodes
export OS_MEM=8192
export CTRL_MEM=8192
export COMP_MEM=4096
export vm_disk_size="30G"

export net_driver="virtio"
