#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh
source $my_dir/../../common/common.sh
source $my_dir/../providers/common/functions.sh

#Specific part of deployment
source $my_dir/${RHOSP_VERSION}_deploy_overcloud.sh

status=$(openstack stack show -f json overcloud | jq ".stack_status")
if [[ ! "$status" =~ 'COMPLETE' || -z "$status" ]] ; then
  echo "ERROR: failed to deploy overcloud: status=$status"
  exit -1
fi

# update hosts file for tf-test
update_undercloud_etc_hosts

if [[ "${ENABLE_NETWORK_ISOLATION,,}" == true ]]; then
  add_vlan_interface ${internal_vlan} ${internal_interface} ${internal_ip_addr} ${internal_net_mask}
  add_vlan_interface ${external_vlan} ${external_interface} ${external_ip_addr} ${external_net_mask}
  # tenant network has no vlan for now, so route is enough
  tenant_ip_route="$tenant_ip_net via $prov_ip dev br-ctlplane"
  sudo ip route add $tenant_ip_route || true
  # save this route persistent
  brctl_cfg_file="/etc/sysconfig/network-scripts/route-br-ctlplane"
  if [ ! -f $brctl_cfg_file ] || ! grep -q "$tenant_ip_route" $brctl_cfg_file ; then
    echo "$tenant_ip_route" | sudo tee -a $brctl_cfg_file
  fi
fi
