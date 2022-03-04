#!/bin/bash

# DEPLOY_POSTFIX is used for environment isolation:
# It changes provider network

export DEPLOY_POSTFIX=${DEPLOY_POSTFIX:-24}
export DEPLOY_POSTFIX_INC=$((DEPLOY_POSTFIX+1))


export overcloud_virt_type="kvm"
export domain="lab1.local"
export undercloud_instance="undercloud"
export prov_inspection_iprange="192.168.${DEPLOY_POSTFIX}.51,192.168.${DEPLOY_POSTFIX}.91"
export prov_dhcp_start="192.168.${DEPLOY_POSTFIX}.100"
export prov_dhcp_end="192.168.${DEPLOY_POSTFIX}.200"
export prov_ip="192.168.${DEPLOY_POSTFIX}.1"
export prov_subnet="192.168.${DEPLOY_POSTFIX}"
export prov_subnet_len="24"
export prov_cidr="192.168.${DEPLOY_POSTFIX}.0/${prov_subnet_len}"
export prov_ip_cidr="${prov_ip}/${prov_subnet_len}"
export fixed_vip="192.168.${DEPLOY_POSTFIX}.250"

#RHOSP16 additional parameters for undercloud.conf
export undercloud_admin_host="${prov_subnet}.3"
export undercloud_public_host="${prov_subnet}.4"

# Interfaces for providing tests run (need only if network isolation enabled)
export internal_vlan="${internal_vlan:-10}"
export internal_interface="${internal_interface:-eth1}"
export internal_ip_addr="10.1.${DEPLOY_POSTFIX}.5"
export internal_net_mask="${internal_net_mask:-"255.255.255.0"}"
export internal_cidr="10.1.${DEPLOY_POSTFIX}.0/24"
export internal_allocation_pool="[{'start': '10.1.${DEPLOY_POSTFIX}.10', 'end': '10.1.${DEPLOY_POSTFIX}.200'}]"
export internal_default_route="10.1.${DEPLOY_POSTFIX}.1"

export external_vlan="${external_vlan:-20}"
export external_interface="${external_interface:-eth1}"
export external_ip_addr="10.${DEPLOY_POSTFIX}.2.5"
export external_net_mask="${external_net_mask:-255.255.255.0}"
export external_cidr="10.2.${DEPLOY_POSTFIX}.0/24"
export external_allocation_pool="[{'start': '10.2.${DEPLOY_POSTFIX}.10', 'end': '10.2.${DEPLOY_POSTFIX}.200'}]"
export external_default_route="10.2.${DEPLOY_POSTFIX}.1"

export storage_vlan="${storage_vlan:-30}"
export storage_cidr="10.3.${DEPLOY_POSTFIX}.0/24"
export storage_allocation_pool="[{'start': '10.3.${DEPLOY_POSTFIX}.10', 'end': '10.3.${DEPLOY_POSTFIX}.200'}]"

export storage_mgmt_vlan="${storage_mgmt_vlan:-40}"
export storage_mgmt_cidr="10.4.${DEPLOY_POSTFIX}.0/24"
export storage_mgmt_allocation_pool="[{'start': '10.4.${DEPLOY_POSTFIX}.10', 'end': '10.4.${DEPLOY_POSTFIX}.200'}]"

export tenant_cidr="10.0.${DEPLOY_POSTFIX}.0/24"
export tenant_allocation_pool="[{'start': '10.0.${DEPLOY_POSTFIX}.10', 'end': '10.0.${DEPLOY_POSTFIX}.200'}]"

# TODO: rework after AGENT_NODES, CONTROLLER_NODES be used as an input for rhosp
export overcloud_cont_instance="${overcloud_cont_instance-1,2,3}"
export overcloud_ctrlcont_instance="${overcloud_ctrlcont_instance-1,2,3}"
export overcloud_compute_instance="${overcloud_compute_instance-1}"
export overcloud_dpdk_instance="${overcloud_dpdk_instance-1}"
export overcloud_sriov_instance="${overcloud_sriov_instance-1}"
export overcloud_ceph_instance="${overcloud_ceph_instance-1,2,3}"

# to allow nova to use hp as well (2 are used by vrouter)
export vrouter_huge_pages_1g="32"

#SRIOV parameters
export sriov_physical_interface="${sriov_physical_interface:-ens2f3}"
export sriov_physical_network="${sriov_physical_network:-sriov1}"
export sriov_vf_number="${sriov_vf_number:-4}"

# IPA params
export ipa_instance="ipa"
#export ipa_mgmt_ip="$ipa_mgmt_ip" - defined outside
export ipa_prov_ip="192.168.${DEPLOY_POSTFIX}.5"
