#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# NOTE: to let run this by user
export WORKSPACE=${WORKSPACE:-$HOME}
export JOB_NAME=${JOB_NAME:-'manual'}

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env" || /bin/true

base_name=$(get_vm_name)

for vm_name in `virsh list --all | grep "$base_name" | awk '{print $2}'` ; do
  delete_domain $vm_name
  vol_path=$(get_pool_path $POOL_NAME)
  vol_name="$vm_name.qcow2"
  delete_volume $vol_name $POOL_NAME
  for ((index=0; index<5; ++index)); do
    delete_volume "$vm_name-$index.qcow2" $POOL_NAME
  done
done

net_name=${KVM_NETWORK}_1
delete_network_dhcp $net_name

sudo bash -c "cat /dev/null > /var/lib/libvirt/dnsmasq/${KVM_BRIDGE}_1.status"
