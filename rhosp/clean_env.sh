#!/bin/bash -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


source "$my_dir/env_desc.sh"
source "$my_dir/virsh_functions"

# delete stack to unregister nodes
#ssh_opts="-i $ssh_key_dir/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
#ssh_addr="root@${mgmt_ip}"
#ssh -T $ssh_opts $ssh_addr "sudo -u stack /home/stack/overcloud-delete.sh" || true
# unregister undercloud
#ssh -T $ssh_opts $ssh_addr "sudo subscription-manager unregister" || true

delete_network management
delete_network provisioning
#delete_network external

delete_network_dhcp $NET_NAME_MGMT
delete_network_dhcp $NET_NAME_PROV

delete_domains rhosp13-overcloud

vol_path=$(get_pool_path $poolname)
rhel_unregister_system $vol_path/$undercloud_vm_volume || true

delete_volume $undercloud_vm_volume $poolname
for vol in `virsh vol-list $poolname | awk "/rhosp13-overcloud-/ {print \$1}"` ; do
#rhel_unregister_system $vol_path/$vol || true
delete_volume $vol $poolname
done

for i in `virsh list --all | grep rhosp13 | awk '{print $2}'`; do virsh destroy $i; virsh undefine $i; done
