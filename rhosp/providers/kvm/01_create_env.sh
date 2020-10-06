#!/bin/bash -ex


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source rhosp-environment.sh
source $my_dir/virsh_functions

# VBMC base port for IPMI management
VBMC_PORT_BASE=16000

OS_MEM=${OS_MEM:-8192}
CTRL_MEM=${CTRL_MEM:-8192}
COMP_MEM=${COMP_MEM:-8192}
IPA_MEM=${COMP_MEM:-16384}

vm_disk_size=${vm_disk_size:-30G}
net_driver=${net_driver:-virtio}

if [[ $RHEL_VERSION == 'rhel8' ]]; then
   rhel_version_libvirt='rhl8.0'
else
   rhel_version_libvirt=$RHEL_VERSION
fi

# check if environment is present
assert_env_exists $undercloud_vmname

# create networks and setup DHCP rules
create_network_dhcp $NET_NAME_MGMT $mgmt_subnet $BRIDGE_NAME_MGMT
update_network_dhcp $NET_NAME_MGMT $undercloud_vmname $undercloud_mgmt_mac $instance_ip
if [[ -n "$ENABLE_TLS" ]] ; then
  update_network_dhcp $NET_NAME_MGMT $ipa_vmname $ipa_mgmt_mac $ipa_mgmt_ip
fi

if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
  create_network_dhcp $NET_NAME_PROV $prov_subnet $BRIDGE_NAME_PROV 'no' 'no_forward'
else
  create_network_dhcp $NET_NAME_PROV $prov_subnet $BRIDGE_NAME_PROV 'yes' 'no_forward'
fi

# create pool
create_pool $poolname
pool_path=$(get_pool_path $poolname)

function create_root_volume() {
  local name=$1
  create_volume $name $poolname $vm_disk_size
}

function define_overcloud_vms() {
  local name=$1
  local mem=$2
  local vbmc_port=$3
  local vcpu=${4:-2}
  local vol_name=$name
  local vm_name="$vol_name"
  create_root_volume $vol_name
  define_machine $vm_name $vcpu $mem $rhel_version_libvirt $NET_NAME_PROV "${pool_path}/${vol_name}.qcow2"
  start_vbmc $vbmc_port $vm_name $mgmt_gateway $IPMI_USER $IPMI_PASSWORD
}

vbmc_port=$VBMC_PORT_BASE
for i in $(echo $overcloud_cont_instance | sed 's/,/ /g') ; do
  define_overcloud_vms $i $OS_MEM $vbmc_port 4
  (( vbmc_port+=1 ))
done
for i in $(echo $overcloud_compute_instance | sed 's/,/ /g') ; do
  define_overcloud_vms $i $COMP_MEM $vbmc_port 4
  (( vbmc_port+=1 ))
done
define_overcloud_vms $overcloud_ctrlcont_instance $CTRL_MEM $vbmc_port 4
(( vbmc_port+=1 ))

# copy image for undercloud and resize them
sudo cp -p $BASE_IMAGE $pool_path/$undercloud_vm_volume
image_customize $pool_path/$undercloud_vm_volume $undercloud_instance $ssh_public_key $domain $prov_ip

if [[ -n "$ENABLE_TLS" ]] ; then
  sudo cp -p $BASE_IMAGE $pool_path/$ipa_vm_volume
  image_customize $pool_path/$ipa_vm_volume $ipa_vmname $ssh_public_key $domain $ipa_prov_ip
fi

#check that nbd kernel module is loaded
if ! sudo lsmod |grep '^nbd ' ; then
  sudo modprobe nbd max_part=8
fi

function _start_vm() {
  local name=$1
  local image=$2
  local mgmt_mac=$3
  local prov_mac=$4
  local ram=${5:-16384}

  # define and start machine
  sudo virt-install --name=$name \
    --ram=$ram \
    --vcpus=4,cores=4 \
    --cpu host \
    --memorybacking hugepages=on \
    --os-type=linux \
    --os-variant=$rhel_version_libvirt \
    --virt-type=kvm \
    --disk "path=$image",size=40,cache=writeback,bus=virtio \
    --boot hd \
    --noautoconsole \
    --network network=$NET_NAME_MGMT,model=$net_driver,mac=$mgmt_mac \
    --network network=$NET_NAME_PROV,model=$net_driver,mac=$prov_mac \
    --graphics vnc,listen=0.0.0.0
}

_start_vm "$undercloud_vmname" "$pool_path/$undercloud_vm_volume" \
  $undercloud_mgmt_mac $undercloud_prov_mac

if [[ -n "$ENABLE_TLS" ]] ; then
  _start_vm "$ipa_vmname" "$pool_path/$ipa_vm_volume" \
    $ipa_mgmt_mac $ipa_prov_mac
fi
