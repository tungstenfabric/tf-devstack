#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

exec 3>&1 1> >(tee /tmp/setup_predeployed_node.log) 2>&1
echo $(date) "------------------ STARTED: $0 -------------------"

cd
source rhosp-environment.sh
source $my_dir/../../common/common.sh
source $my_dir/../../common/functions.sh
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

$my_dir/../../common/rhel_provisioning.sh

if [ -n $NAMESERVER_LIST ]; then
    echo "INFO: Setup DNS servers $NAMESERVER_LIST"
    NS_SERVER1=$(echo $NAMESERVER_LIST | cut -d ',' -f1)
fi

if [[ "$ENABLE_TLS" == "ipa" ]] ; then
   ensure_nameserver $ipa_prov_ip
   ensure_record_in_etc_hosts $ipa_prov_ip "${ipa_instance}.${domain}"
else
   ensure_nameserver ${NS_SERVER1:-"8.8.8.8"}
fi

echo "INFO: source file $my_dir/${RHOSP_MAJOR_VERSION}_configure_registries_overcloud.sh"
source $my_dir/${RHOSP_MAJOR_VERSION}_configure_registries_overcloud.sh

# to avoid slow ssh connect if dns is not available
sudo sed -i 's/.*UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
sudo service sshd reload

ensure_record_in_etc_hosts $prov_ip $undercloud_instance

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
