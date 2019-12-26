#!/bin/bash -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


source "$my_dir/env.sh"
source "$my_dir/virsh_functions"

# delete stack to unregister nodes
ssh_opts="-i $ssh_private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# unregister undercloud
ssh -T $ssh_opts stack@${mgmt_ip} "sudo subscription-manager unregister"

for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
    ssh -T $ssh_opts stack@${ip} "sudo subscription-manager unregister"
done

delete_network management
delete_network provisioning
#delete_network external

delete_network_dhcp $NET_NAME_MGMT
delete_network_dhcp $NET_NAME_PROV

delete_domains rhosp13-overcloud

vol_path=$(get_pool_path $poolname)

delete_volume $undercloud_vm_volume $poolname
for vol in `virsh vol-list $poolname | awk "/rhosp13-overcloud-/ {print \$1}"` ; do
  delete_volume $vol $poolname
done

for i in `virsh list --all | grep rhosp13 | awk '{print $2}'`; do virsh destroy $i; virsh undefine $i; done
