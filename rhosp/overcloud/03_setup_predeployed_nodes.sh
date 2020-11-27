#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source $my_dir/../../common/common.sh
source $my_dir/../providers/common/common.sh

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
if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
   echo "nameserver $ipa_prov_ip" | sudo tee -a /etc/resolv.conf
   if ! sudo grep -q "$domain" /etc/resolv.conf ; then
      sudo sed -i "0,/nameserver/s/\(nameserver.*\)/search ${domain}\n\1/" /etc/resolv.conf
   fi
else
   echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
fi

$my_dir/../providers/common/rhel_provisioning.sh

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

if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
   short_name="$(echo $fqdn | cut -d '.' -f 1)"
   realm="${domain^^}"
   novajoin-ipa-setup \
      --principal admin \
      --password "$ADMIN_PASSWORD" \
      --server ${ipa_instance}.${domain} \
      --realm ${realm} \
      --domain ${domain} \
      --hostname ${fqdn} \
      --otp-file ${fqdn}.otp \
      --precreate

   sudo hostnamectl set-hostname $fqdn
   sudo ipa-client-install --verbose -U -w "$(cat ${fqdn}.otp)" --hostname "$fqdn"

   echo "$ADMIN_PASSWORD" | kinit admin

   function _add_node(){
      local name=$1
      local zone=$2
      local addr=$3
      local services="$4"
      ipa dnsrecord-add --a-ip-address=$addr ${zone} ${name}
      ipa host-add ${name}.${zone}
      local s
      for s in $services ; do
         local principal="${s}/${name}.${zone}@${realm}"
         ipa service-add $principal
         ipa service-add-host --hosts $fqdn $principal
      done
   }

   declare -A networks=( \
      ['ctlplane']='contrail HTTP' \
      ['internalapi']='contrail HTTP novnc-proxy redis rabbitmq mysql libvirt qemu' \
      ['storage']='HTTP' \
      ['storagemgmt']='HTTP' \
      ['external']='HTTP' \
      ['tenant']='contrail' \
   )
   # services
   for net in ${!networks[@]} ; do
      zone="${net}.${domain}"
      if ! ipa dnszone-find ${zone} ; then
         ipa dnszone-add ${zone} || true
      fi
      _add_node "$short_name" "${zone}" "$NODE_IP" "${networks[${net}]}"
      _add_node "overcloud" "${zone}" "$fixed_vip" "haproxy"
   done
   # vip public
   _add_node "overcloud" "$domain" "$fixed_vip" "haproxy"
fi