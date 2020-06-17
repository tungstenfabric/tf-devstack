#!/bin/bash

export RHOSP_VERSION=${RHOSP_VERSION:-"rhosp13"}

export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-docker.io/tungstenfabric}"
export CONTRAIL_CONTAINER_TAG="${CONTRAIL_CONTAINER_TAG:-latest}"

export IPMI_USER=${IPMI_USER:-"ADMIN"}
export IPMI_PASSWORD=${IPMI_PASSWORD:-"ADMIN"}

export prov_ip_cidr="192.168.100.10/24"
export undercloud_local_interface="eth1"
export local_mtu="1500"
export domain="lab1.local"
export undercloud_instance="undercloud"
export prov_inspection_iprange="192.168.100.51,192.168.100.91"
export prov_dhcp_start="192.168.100.100"
export prov_dhcp_end="192.168.100.200"
export prov_ip="192.168.100.10"
export prov_cidr="192.168.100.0/24"
export overcloud_virt_type="qemu"
export prov_subnet_len="24"
export fixed_vip="192.168.100.250"
