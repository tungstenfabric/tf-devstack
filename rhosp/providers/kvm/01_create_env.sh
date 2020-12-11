#!/bin/bash -exu


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source rhosp-environment.sh
source $my_dir/../../../common/common.sh
source $my_dir/virsh_functions

if [[ $RHEL_VERSION == 'rhel8' ]]; then
   rhel_version_libvirt='rhl8.0'
   _default_base_image='/var/lib/libvirt/images/rhel-8.2-x86_64-kvm.qcow2'
else
   rhel_version_libvirt=$RHEL_VERSION
   _default_base_image='/var/lib/libvirt/images/rhel-server-7.9-x86_64-kvm.qcow2'
fi

undercloud_vmname="$RHOSP_VERSION-undercloud-${DEPLOY_POSTFIX}"
undercloud_mgmt_mac="00:16:00:00:${DEPLOY_POSTFIX}:02"
undercloud_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:03"

ipa_mgmt_mac="00:16:00:00:${DEPLOY_POSTFIX}:04"
ipa_prov_mac="00:16:00:00:${DEPLOY_POSTFIX}:05"

BASE_IMAGE=${BASE_IMAGE:-${_default_base_image}}
UNDERCLOUD_MEM=${UNDERCLOUD_MEM:-16384}
IPA_MEM=${IPA_MEM:-4096}
OS_MEM=${OS_MEM:-8192}
CTRL_MEM=${CTRL_MEM:-8192}
COMP_MEM=${COMP_MEM:-8192}

vm_disk_size=${vm_disk_size:-60G}
net_driver=${net_driver:-virtio}

# check if environment is present
assert_env_exists $undercloud_vmname

# create networks and setup DHCP rules
create_network_dhcp $NET_NAME_MGMT $mgmt_subnet
update_network_dhcp $NET_NAME_MGMT $undercloud_vmname $undercloud_mgmt_mac $instance_ip
if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
  update_network_dhcp $NET_NAME_MGMT $ipa_instance $ipa_mgmt_mac $ipa_mgmt_ip
fi

if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
  create_network_dhcp $NET_NAME_PROV $prov_subnet 'no' 'no_forward'
else
  create_network_dhcp $NET_NAME_PROV $prov_subnet 'yes' 'no_forward'
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
for i in $(echo $overcloud_ctrlcont_instance | sed 's/,/ /g') ; do
  define_overcloud_vms $i $CTRL_MEM $vbmc_port 4
  (( vbmc_port+=1 ))
done

# copy image for undercloud and resize them
undercloud_vm_volume="$pool_path/${undercloud_vmname}.qcow2"
sudo cp -p $BASE_IMAGE $undercloud_vm_volume
image_customize $undercloud_vm_volume $undercloud_instance $ssh_public_key $domain $prov_ip

if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
  ipa_vm_volume="$pool_path/${ipa_instance}.qcow2"
  sudo cp -p $BASE_IMAGE $ipa_vm_volume
  image_customize $ipa_vm_volume $ipa_instance $ssh_public_key $domain $ipa_prov_ip
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
  local ram=${5}

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

_start_vm "$undercloud_vmname" "$undercloud_vm_volume" \
  $undercloud_mgmt_mac $undercloud_prov_mac $UNDERCLOUD_MEM

if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
  _start_vm "$ipa_instance" "$ipa_vm_volume" \
    $ipa_mgmt_mac $ipa_prov_mac $IPA_MEM
fi
