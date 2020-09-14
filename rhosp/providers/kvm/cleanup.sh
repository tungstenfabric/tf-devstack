#!/bin/bash -x

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run by root"
   exit 1
fi


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ ! -f "/home/$SUDO_USER/rhosp-environment.sh" ]] ; then
    echo No file "/home/$SUDO_USER/rhosp-environment.sh" exists, exiting
    exit 1
fi
source "/home/$SUDO_USER/rhosp-environment.sh"
source "$my_dir/virsh_functions"

# delete stack to unregister nodes
# unregister undercloud
ssh -T $ssh_opts stack@${mgmt_ip} "sudo subscription-manager unregister"
ssh -T $ssh_opts root@${ipa_mgmt_ip} "subscription-manager unregister"

for ip in $(echo $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip | sed 's/,/ /g'); do
    ssh -T $ssh_opts stack@${ip} "sudo subscription-manager unregister"
done

function delete_node() {
    local name=$1
    local disk=$2
    local pool=${3:-"$poolname"}

    delete_domain $name
    delete_volume "$disk" $pool
}

for i in $(echo $overcloud_cont_instance $overcloud_compute_instance $overcloud_ctrlcont_instance $ipa_vmname | sed 's/,/ /g') ; do
    delete_node $i "$i.qcow2" 
done

delete_network_dhcp $NET_NAME_MGMT
delete_network_dhcp $NET_NAME_PROV

virsh pool-destroy $poolname
virsh pool-undefine $poolname

rm -rf "/home/$SUDO_USER/rhosp-environment.sh" "/home/$SUDO_USER/instackenv.json" "/home/$SUDO_USER/.tf"
