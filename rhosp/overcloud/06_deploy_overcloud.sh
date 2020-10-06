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

# patch hosts to resole overcloud by fqdn
echo "INFO: update /etc/hosts for overcloud vips fqdns"
sudo sed -i "/overcloud.${domain}/d" /etc/hosts
sudo sed -i "/overcloud.internalapi.${domain}/d" /etc/hosts
sudo sed -i "/overcloud.ctlplane.${domain}/d" /etc/hosts

if [[ -n "$overcloud_cont_prov_ip" ]]; then
  sudo bash -c "echo \"${overcloud_cont_prov_ip} overcloud.${domain}\" >> /etc/hosts"
  sudo bash -c "echo \"${overcloud_cont_prov_ip} overcloud.internalapi.${domain}\" >> /etc/hosts"
  sudo bash -c "echo \"${overcloud_cont_prov_ip} overcloud.ctlplane.${domain}\" >> /etc/hosts"
else
  sudo bash -c "echo \"$(get_vip public_virtual_ip) overcloud.${domain}\" >> /etc/hosts"
  sudo bash -c "echo \"$(get_vip internal_api_virtual_ip) overcloud.internalapi.${domain}\" >> /etc/hosts"
  sudo bash -c "echo \"${fixed_vip} overcloud.ctlplane.${domain}\" >> /etc/hosts"
fi
cat /etc/hosts

if [[ "${ENABLE_NETWORK_ISOLATION,,}" == true ]]; then
  add_vlan_interface ${internal_vlan} ${internal_interface} ${internal_ip_addr} ${internal_net_mask}
  add_vlan_interface ${external_vlan} ${external_interface} ${external_ip_addr} ${external_net_mask}
fi
