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

# patch hosts to resole overcloud by fqdn
sudo sed -e "/overcloud.${domain}/d" /etc/hosts
sudo bash -c "echo \"${fixed_vip} overcloud.${domain}\" >> /etc/hosts"

# add ip route for fixed_vip
sudo ip route add ${fixed_vip}/32 dev br-ctlplane || {
  echo "WARNING: ip route add ${fixed_vip}/32 dev br-ctlplane is already set"
  ip route
}
