#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


cd ~
source ./stackrc
source ./rhosp-environment.sh

#Specific part of deployment
source $my_dir/${RHOSP_VERSION}_deploy_overcloud.sh

status=$(openstack stack show -f json overcloud | jq ".stack_status")
if [[ ! "$status" =~ 'COMPLETE' ]] ; then
  echo "ERROR: failed to deploy overcloud"
  exit -1
fi

ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
internal_vip=$(ssh $ssh_opts $SSH_USER@$overcloud_cont_prov_ip sudo hiera -c /etc/puppet/hiera.yaml internal_api_virtual_ip)

# patch hosts to resole overcloud by fqdn
sudo sed -e "/overcloud.${domain}/d" /etc/hosts
sudo bash -c "echo \"${fixed_vip} overcloud.${domain}\" >> /etc/hosts"
sudo sed -e "/overcloud.internalapi.${domain}/d" /etc/hosts
sudo bash -c "echo \"${internal_vip} overcloud.internalapi.${domain}\" >> /etc/hosts"

# add ip route for vips
sudo ip route add ${fixed_vip}/32 dev br-ctlplane
if [[ "$internal_vip" != "$fixed_vip" ]] ; then
  sudo ip route add ${internal_vip}/32 dev br-ctlplane
fi
