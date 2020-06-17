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
if [[ ! "$status" =~ 'COMPLETE' ]] ; then
  echo "ERROR: failed to deploy overcloud"
  exit -1
fi

CONTROLLER_NODE=$(get_servers_ips_by_flavor control | awk '{print $1}')

if [[ -n "$CONTROLLER_NODE" ]]; then
  ssh $ssh_opts -q $SSH_USER@$CONTROLLER_NODE exit || SSH_USER=heat-admin
  internal_vip=$(ssh $ssh_opts $SSH_USER@$CONTROLLER_NODE sudo hiera -c /etc/puppet/hiera.yaml internal_api_virtual_ip)

  # patch hosts to resole overcloud by fqdn
  sudo sed -e "/overcloud.${domain}/d" /etc/hosts
  sudo bash -c "echo \"${fixed_vip} overcloud.${domain}\" >> /etc/hosts"
  sudo sed -e "/overcloud.internalapi.${domain}/d" /etc/hosts
  sudo bash -c "echo \"${internal_vip} overcloud.internalapi.${domain}\" >> /etc/hosts"

  # add ip route for vips
  for addr in $(echo -e "${fixed_vip}/32\n${internal_vip}/32" | sort -u) ; do
    if [[ -z "$(ip route show $addr)" ]] ; then
      sudo ip route add $addr dev br-ctlplane
    fi
  done
fi
