#!/bin/bash

export RHEL_POOL_ID=8a85f99970453685017057d235142b3b

state="$(set +o)"
[[ "$-" =~ e ]] && state+="; set -e"

set +x
#Red Hat credentials
export RHEL_PASSWORD=$RHEL_PASSWORD
export RHEL_USER=$RHEL_USER
eval "$state"

export undercloud_local_interface=${undercloud_local_interface:-"eth1"}
export contrail_dpdk_driver=${contrail_dpdk_driver:-"uio_pci_generic"}
