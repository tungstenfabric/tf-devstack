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

for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
    ssh -T $ssh_opts stack@${ip} "sudo subscription-manager unregister"
done

for i in $(echo $overcloud_cont_instance | sed 's/,/ /g') ; do
    delete_domain $i
    delete_volume "$i.qcow2" $poolname
done

delete_domain $overcloud_compute_instance
delete_volume "$overcloud_compute_instance.qcow2" $poolname

delete_domain $overcloud_ctrlcont_instance
delete_volume "$overcloud_ctrlcont_instance.qcow2" $poolname

delete_domain $undercloud_vmname
delete_volume $undercloud_vm_volume $poolname

delete_domain $ipa_vmname
delete_volume $ipa_vm_volume $poolname


delete_network_dhcp $NET_NAME_MGMT
delete_network_dhcp $NET_NAME_PROV

virsh pool-destroy $poolname
virsh pool-undefine $poolname

rm -rf "/home/$SUDO_USER/rhosp-environment.sh" "/home/$SUDO_USER/instackenv.json" "/home/$SUDO_USER/.tf"



