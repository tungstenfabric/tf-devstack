#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh

#Set default gateway to undercloud
default_dev=$(sudo ip route get $prov_ip | grep -o "dev.*" | awk '{print $2}')
if [[ -z "$default_dev" || 'lo' == "$default_dev" ]] ; then
   echo "ERROR: undercloud node is not reachable from overcloud via prov network"
   exit 1
fi

cfg_file="/etc/sysconfig/network-scripts/ifcfg-$default_dev"
sudo ip route replace default via ${prov_ip} dev $default_dev
sudo sed -i '/^GATEWAY[ ]*=/d' $cfg_file
echo "GATEWAY=${prov_ip}" | sudo tee -a $cfg_file
sudo sed -i '/nameserver/d'  /etc/resolv.conf
echo 'nameserver 8.8.8.8' | sudo tee -a /etc/resolv.conf

sudo -E $my_dir/../providers/common/rhel_provisioning.sh

source $my_dir/${RHOSP_VERSION}_configure_registries_overcloud.sh

# to avoid slow ssh connect if dns is not available
sudo sed -i 's/.*UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
sudo service sshd reload

undercloud_hosts_entry="$prov_ip    $undercloud_instance"
[ -n "$domain" ] && undercloud_hosts_entry+=".$domain    $undercloud_instance"
if ! grep -q "$undercloud_hosts_entry" /etc/hosts ; then
   echo "$undercloud_hosts_entry" | sudo tee -a /etc/hosts
fi

fqdn=$(hostname -f)
short_name=$(hostname)
hosts_names=$fqdn
[[ "$short_name" != "$short_name" ]] && hosts_names+="    $short_name"
if ! grep -q "$hosts_names" /etc/hosts ; then
   default_ip=$(sudo ip addr show dev $default_dev | awk '/inet /{print($2)}' | cut -d '/' -f 1)
   echo "INFO: add resolving $hosts_names to $default_ip"
   [ -n "$default_ip" ] || {
      echo "ERROR: failed to detect ip addr for dev $default_dev"
      exit 1
   }
   echo "$default_ip    $hosts_names" | sudo tee -a /etc/hosts
fi
