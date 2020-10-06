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
echo "INFO: remove from /etc/hosts old overcloud vips fqdns if any"
sudo sed -i "/overcloud.${domain}/d" /etc/hosts
sudo sed -i "/overcloud.internalapi.${domain}/d" /etc/hosts
sudo sed -i "/overcloud.ctlplane.${domain}/d" /etc/hosts

if [ -n "$overcloud_cont_prov_ip" ] ; then
  public_vip=$overcloud_cont_prov_ip
  internal_api_vip=$overcloud_cont_prov_ip
  ctlplane_vip=$overcloud_cont_prov_ip
else
  public_vip=$(get_vip public_virtual_ip)
  internal_api_vip=$(get_vip internal_api_virtual_ip)
  ctlplane_vip=$fixed_vip
fi
  echo "INFO: update /etc/hosts for overcloud vips fqdns"
  cat <<EOF | sudo tee -a /etc/hosts
${public_vip} overcloud.${domain}
${internal_api_vip} overcloud.internalapi.${domain}
${ctlplane_vip} overcloud.ctlplane.${domain}
EOF
sudo cat /etc/hosts

if [[ "${ENABLE_NETWORK_ISOLATION,,}" == true ]]; then
  add_vlan_interface ${internal_vlan} ${internal_interface} ${internal_ip_addr} ${internal_net_mask}
  add_vlan_interface ${external_vlan} ${external_interface} ${external_ip_addr} ${external_net_mask}
fi
