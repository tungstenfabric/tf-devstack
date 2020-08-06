#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../providers/common/functions.sh"

cd ~
source ./stackrc
source ./rhosp-environment.sh


#Specific part of deployment
source $my_dir/${RHOSP_VERSION}_deploy_overcloud.sh

status=$(openstack stack show -f json overcloud | jq ".stack_status")
if [[ ! "$status" =~ 'COMPLETE' || -z "$status" ]] ; then
  echo "ERROR: failed to deploy overcloud: status=$status"
  exit -1
fi

# patch hosts to resole overcloud by fqdn
sudo sed -e "/overcloud.${domain}/d" /etc/hosts
sudo sed -e "/overcloud.internalapi.${domain}/d" /etc/hosts
sudo sed -e "/overcloud.ctlplane.${domain}/d" /etc/hosts

if [[ -n "$overcloud_cont_prov_ip" ]]; then
  sudo bash -c "echo \"${overcloud_cont_prov_ip} overcloud.${domain}\" >> /etc/hosts"
  sudo bash -c "echo \"${overcloud_cont_prov_ip} overcloud.internalapi.${domain}\" >> /etc/hosts"
  sudo bash -c "echo \"${overcloud_cont_prov_ip} overcloud.ctlplane.${domain}\" >> /etc/hosts"
else
  sudo bash -c "echo \"$(get_vip public_virtual_ip) overcloud.${domain}\" >> /etc/hosts"
  sudo bash -c "echo \"$(get_vip internal_api_virtual_ip) overcloud.internalapi.${domain}\" >> /etc/hosts"
  sudo bash -c "echo \"${fixed_vip} overcloud.ctlplane.${domain}\" >> /etc/hosts"
fi
