#!/bin/bash

# DEPLOY_POSTFIX is used for environment isolation:
# vm names, pools, management and provider networks,
# volumes, mac addresses.
export DEPLOY_POSTFIX=${DEPLOY_POSTFIX:-20}
export DEPLOY_POSTFIX_INC=$((DEPLOY_POSTFIX+1))

export RHOSP_VERSION=${RHOSP_VERSION:-"rhosp13"}

export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-"latest"}

export BASE_IMAGE=${BASE_IMAGE:-"/home/jenkins/rhel_7.7.qcow2"}

# SSH public key for user stack
export ssh_private_key="/home/jenkins/.ssh/id_rsa"
export ssh_public_key="/home/jenkins/.ssh/id_rsa.pub"


export poolname="rdimages_${DEPLOY_POSTFIX}"

# define undercloud virtual machine's names
export undercloud_prefix="undercloud"
export undercloud_vmname="$RHOSP_VERSION-undercloud-${DEPLOY_POSTFIX}"


# define virtual machine's volumes

export undercloud_vm_volume="$undercloud_prefix.qcow2"

# network names and settings
export BRIDGE_NAME_MGMT="mgmt-${DEPLOY_POSTFIX}"
export BRIDGE_NAME_PROV="prov-${DEPLOY_POSTFIX}"
export NET_NAME_MGMT=${BRIDGE_NAME_MGMT}
export NET_NAME_PROV=${BRIDGE_NAME_PROV}


# IPMI
export IPMI_USER="stack"
export IPMI_PASSWORD="qwe123QWE"

# VBMC base port for IPMI management
export VBMC_PORT_BASE=16000

# IP, subnets
export mgmt_subnet="192.168.${DEPLOY_POSTFIX}"
export mgmt_gateway="${mgmt_subnet}.1"
export mgmt_ip="${mgmt_subnet}.2"

export prov_subnet="192.168.${DEPLOY_POSTFIX_INC}"
export prov_gateway="${prov_subnet}.1"
export prov_cidr="${prov_subnet}.0/24"
export prov_subnet_len=24
export prov_ip="${prov_subnet}.2"
export prov_ip_cidr="${prov_ip}/24"

export fixed_vip="${prov_subnet}.200"
export fixed_controller_ip="${prov_subnet}.211"

# Undercloud MAC addresses
export undercloud_mgmt_mac="00:16:00:00:${DEPLOY_POSTFIX}:02"
export undercloud_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:03"
export undercloud_instance="undercloud-${DEPLOY_POSTFIX}"
export domain="localdomain"

#RHOSP16 additional parameters for undercloud.conf
export undercloud_admin_host="${prov_subnet}.3"
export undercloud_public_host="${prov_subnet}.4"

# ip addresses for overcloud nodes
export overcloud_cont_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:10"
export overcloud_compute_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:11"
export overcloud_ctrlcont_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:12"

export overcloud_cont_prov_ip="${prov_subnet}.10"
export overcloud_compute_prov_ip="${prov_subnet}.11"
export overcloud_ctrlcont_prov_ip="${prov_subnet}.12"
export overcloud_cont_instance="$RHOSP_VERSION-overcloud-cont-${DEPLOY_POSTFIX}"
export overcloud_compute_instance="$RHOSP_VERSION-overcloud-compute-${DEPLOY_POSTFIX}"
export overcloud_ctrlcont_instance="$RHOSP_VERSION-overcloud-ctrlcont-${DEPLOY_POSTFIX}"


# VM nodes
export OS_MEM=8192
export CTRL_MEM=8192
export COMP_MEM=8192
export vm_disk_size="60G"

export net_driver="virtio"
export overcloud_virt_type="kvm"

