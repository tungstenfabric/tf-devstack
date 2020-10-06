#!/bin/bash

# DEPLOY_POSTFIX is used for environment isolation:
# vm names, pools, management and provider networks,
# volumes, mac addresses.
export DEPLOY_POSTFIX=${DEPLOY_POSTFIX:-20}
export DEPLOY_POSTFIX_INC=$((DEPLOY_POSTFIX+1))

export RHOSP_VERSION=${RHOSP_VERSION:-"rhosp13"}

export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-docker.io/tungstenfabric}"
export CONTRAIL_CONTAINER_TAG="${CONTRAIL_CONTAINER_TAG:-latest}"

export BASE_IMAGE=${BASE_IMAGE:-~/rhel_7.7.qcow2}

# SSH public key for user stack
export SSH_USER=${SSH_USER:-'stack'}
export ssh_private_key=${ssh_private_key:-~/.ssh/id_rsa}
export ssh_public_key=${ssh_public_key:-~/.ssh/id_rsa.pub}

export ssh_opts="-i $ssh_private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no"

export poolname="rdimages_${DEPLOY_POSTFIX}"

# define undercloud virtual machine's names
export undercloud_vmname="$RHOSP_VERSION-undercloud-${DEPLOY_POSTFIX}"
export undercloud_vm_volume="${undercloud_vmname}.qcow2"

export ipa_vmname="$RHOSP_VERSION-ipa-${DEPLOY_POSTFIX}"
export ipa_vm_volume="${ipa_vmname}.qcow2"


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
export instance_ip="${mgmt_subnet}.2"

export prov_subnet="192.168.${DEPLOY_POSTFIX_INC}"
export prov_gateway="${prov_subnet}.1"
export prov_cidr="${prov_subnet}.0/24"
export prov_subnet_len=24
export prov_ip="${prov_subnet}.2"
export prov_ip_cidr="${prov_ip}/24"
export prov_inspection_iprange="${prov_subnet}.150,${prov_subnet}.170"
export prov_dhcp_start=${prov_subnet}.100
export prov_dhcp_end=${prov_subnet}.149

export fixed_vip="${prov_subnet}.200"
export fixed_controller_ip="${prov_subnet}.211"

# Undercloud MAC addresses
export undercloud_mgmt_mac="00:16:00:00:${DEPLOY_POSTFIX}:02"
export undercloud_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:03"
export undercloud_instance="$RHOSP_VERSION-undercloud-${DEPLOY_POSTFIX}"
export domain="dev.localdomain"

# IPA params
export ipa_instance="$RHOSP_VERSION-ipa-${DEPLOY_POSTFIX}"
export ipa_mgmt_mac="00:16:00:00:${DEPLOY_POSTFIX}:04"
export ipa_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:05"
export ipa_mgmt_ip="${mgmt_subnet}.3"
export ipa_prov_ip="${prov_subnet}.5"

#RHOSP16 additional parameters for undercloud.conf
export undercloud_admin_host="${prov_subnet}.3"
export undercloud_public_host="${prov_subnet}.4"

# ip addresses for overcloud nodes
export overcloud_cont_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:10"
export overcloud_compute_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:20"
export overcloud_ctrlcont_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:30"

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
