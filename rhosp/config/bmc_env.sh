#!/bin/bash

export RHOSP_VERSION=${RHOSP_VERSION:-"rhosp13"}

export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-docker.io/tungstenfabric}"
export CONTRAIL_CONTAINER_TAG="${CONTRAIL_CONTAINER_TAG:-latest}"

export IPMI_USER=${IPMI_USER:-"ADMIN"}
export IPMI_PASSWORD=${IPMI_PASSWORD:-"ADMIN"}

export SSH_USER=$(whoami)

export overcloud_virt_type="qemu"
export undercloud_local_interface="eth1"
export local_mtu="1500"
export domain="lab1.local"
export undercloud_instance="undercloud"
export prov_inspection_iprange="192.168.24.51,192.168.24.91"
export prov_dhcp_start="192.168.24.100"
export prov_dhcp_end="192.168.24.200"
export prov_ip="192.168.24.1"
export prov_subnet_len="24"
export prov_cidr="192.168.24.0/${prov_subnet_len}"
export prov_ip_cidr="${prov_ip}/${prov_subnet_len}"
export fixed_vip="192.168.24.250"

# Interfaces for providing tests run
export internal_vlan="vlan710"
export internal_interface="eth1"
export internal_ip_addr="10.1.0.5"
export internal_net_mask="255.255.255.0"

export external_vlan="vlan720"
export external_interface="eth1"
export external_ip_addr="10.2.0.5"
export external_net_mask="255.255.255.0"

export tenant_vlan="vlan730"
export tenant_interface="eth1"
export tenant_ip_addr="10.2.0.5"
export tenant_net_mask="255.255.255.0"
