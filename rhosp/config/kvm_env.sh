#!/bin/bash

# DEPLOY_POSTFIX is used for environment isolation:
# vm names, pools, management and provider networks,
# volumes, mac addresses.
export DEPLOY_POSTFIX=${DEPLOY_POSTFIX:-20}
export DEPLOY_POSTFIX_INC=$((DEPLOY_POSTFIX+1))

# VBMC base port for IPMI management
export VBMC_PORT_BASE=$(( 16000 + DEPLOY_POSTFIX ))

export poolname="rdimages_${DEPLOY_POSTFIX}"


# network names and settings
export NET_NAME_MGMT="mgmt-${DEPLOY_POSTFIX}"
export NET_NAME_PROV="prov-${DEPLOY_POSTFIX}"

# IP, subnets
export mgmt_subnet="192.168.${DEPLOY_POSTFIX}"
export mgmt_gateway="${mgmt_subnet}.1"
export instance_ip="${mgmt_subnet}.2"

export prov_subnet="192.168.${DEPLOY_POSTFIX_INC}"
export prov_cidr="${prov_subnet}.0/24"
export prov_subnet_len=24
export prov_ip="${prov_subnet}.2"
export prov_ip_cidr="${prov_ip}/24"
export prov_inspection_iprange="${prov_subnet}.150,${prov_subnet}.170"
export prov_dhcp_start=${prov_subnet}.100
export prov_dhcp_end=${prov_subnet}.149

# L3MH
export NET_NAME_L3MH_1="l3mh1-${DEPLOY_POSTFIX}"
export NET_NAME_L3MH_2="l3mh2-${DEPLOY_POSTFIX}"
export l3mh_subnet1="172.16.10.1"
export l3mh_subnet2="172.16.20.1"

# Other
export fixed_vip="${prov_subnet}.200"

export domain="dev.clouddomain"

# Undercloud
export undercloud_instance="${RHOSP_VERSION//./-}-undercloud-${DEPLOY_POSTFIX}"
# rhosp16 only
export undercloud_admin_host="${prov_subnet}.3"
export undercloud_public_host="${prov_subnet}.4"

# IPA params
export ipa_instance="${RHOSP_VERSION//./-}-ipa-${DEPLOY_POSTFIX}"
export ipa_mgmt_ip="${mgmt_subnet}.3"
export ipa_prov_ip="${prov_subnet}.5"

# Overcloud
export overcloud_virt_type="kvm"

# to add name into rhosp-environment.sh
export overcloud_cont_instance="${overcloud_cont_instance}"
export overcloud_compute_instance="${overcloud_compute_instance}"
export overcloud_ctrlcont_instance="${overcloud_ctrlcont_instance}"

# to allow vrouter to use 1gb pages
export vrouter_huge_pages_1g='2'
