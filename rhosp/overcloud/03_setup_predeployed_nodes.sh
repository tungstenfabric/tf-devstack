#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source $my_dir/../../common/common.sh
source $my_dir/../providers/common/common.sh
source $my_dir/../providers/common/functions.sh

#Set default gateway to undercloud
default_dev=$(sudo ip route get $prov_ip | grep -o "dev.*" | awk '{print $2}')
default_ip=$(sudo ip addr show dev $default_dev | awk '/inet /{print($2)}' | cut -d '/' -f 1)
if [[ -z "$default_dev" || 'lo' == "$default_dev" || -z "$default_ip" ]] ; then
   echo "ERROR: undercloud node is not reachable from overcloud via prov network"
   exit 1
fi

cfg_file="/etc/sysconfig/network-scripts/ifcfg-$default_dev"
sudo ip route replace default via ${prov_ip} dev $default_dev
sudo sed -i '/^GATEWAY[ ]*=/d' $cfg_file
echo "GATEWAY=${prov_ip}" | sudo tee -a $cfg_file

sudo sed -i '/nameserver/d'  /etc/resolv.conf
if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
   echo "nameserver $ipa_prov_ip" | sudo tee -a /etc/resolv.conf
   if ! sudo grep -q "$domain" /etc/resolv.conf ; then
      sudo sed -i "0,/nameserver/s/\(nameserver.*\)/search ${domain}\n\1/" /etc/resolv.conf
   fi
else
   echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
fi

$my_dir/../providers/common/rhel_provisioning.sh

echo "INFO: source file $my_dir/${RHOSP_MAJOR_VERSION}_configure_registries_overcloud.sh"
source $my_dir/${RHOSP_MAJOR_VERSION}_configure_registries_overcloud.sh

# to avoid slow ssh connect if dns is not available
sudo sed -i 's/.*UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
sudo service sshd reload

undercloud_hosts_entry="$prov_ip    $undercloud_instance"
[ -n "$domain" ] && undercloud_hosts_entry+=".$domain    $undercloud_instance"
if ! grep -q "$undercloud_hosts_entry" /etc/hosts ; then
   echo "$undercloud_hosts_entry" | sudo tee -a /etc/hosts
fi

fqdn=$(hostname -f)
short_name=$(hostname -s)
hosts_names=$fqdn
[[ "$short_name" != "$short_name" ]] && hosts_names+="    $short_name"
if ! grep -q "$hosts_names" /etc/hosts ; then
   echo "INFO: add resolving $hosts_names to $default_ip"
   [ -n "$default_ip" ] || {
      echo "ERROR: failed to detect ip addr for dev $default_dev"
      exit 1
   }
   echo "$default_ip    $hosts_names" | sudo tee -a /etc/hosts
fi

if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
   short_name="$(echo $fqdn | cut -d '.' -f 1)"
   novajoin-ipa-setup \
      --principal admin \
      --password "$ADMIN_PASSWORD" \
      --server ${ipa_instance}.${domain} \
      --realm ${domain^^} \
      --domain ${domain} \
      --hostname ${fqdn} \
      --otp-file ${fqdn}.otp \
      --precreate

   sudo hostnamectl set-hostname $fqdn
   sudo ipa-client-install --verbose -U -w "$(cat ${fqdn}.otp)" --hostname "$fqdn"

   echo "$ADMIN_PASSWORD" | kinit admin

   # services
   # (zone are added before at _overcloud)
   for net in ${!RHOSP_NETWORKS[@]} ; do
      zone="${net}.${domain}"
      node_ip=$(sudo awk "/$fqdn/{print(\$1)}" /etc/hosts)
      [ -n "$node_ip" ] || node_ip="$default_ip"
      add_node_to_ipa "$short_name" "${zone}" "$node_ip" "${RHOSP_NETWORKS[${net}]}" "${fqdn}"
   done
fi
