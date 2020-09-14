#!/bin/bash

export RHEL_POOL_ID=8a85f99970453685017057d235142b3b

export undercloud_local_interface=${undercloud_local_interface:-"eth1"}
export keystone_admin_api_network=${keystone_admin_api_network:-"ctlplane"}

state="$(set +o); set -$(echo $- | tr -d 'i')"
set +x
#Red Hat credentials
export RHEL_PASSWORD=$RHEL_PASSWORD
export RHEL_USER=$RHEL_USER
eval "$state"
