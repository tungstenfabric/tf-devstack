
function create_flavor() {
  local name=$1
  local profile=${2:-''}
  openstack flavor create --id auto --ram 1000 --disk 29 --vcpus 2 $name
  openstack flavor set --property "cpu_arch"="x86_64" \
                       --property "capabilities:boot_option"="local" \
                       $name
  if [[ -n "$profile" ]] ; then
    openstack flavor set --property "capabilities:profile"="${profile}" $name
  else
    echo "Skip flavor profile propery set for $name"
  fi
}

create_flavor 'control' 'controller'
create_flavor 'compute' 'compute'
create_flavor 'contrail-controller' 'contrail-controller'
create_flavor 'compute-dpdk' 'compute-dpdk'
create_flavor 'compute-sriov' 'compute-sriov'
create_flavor 'ceph-storage' 'ceph-storage'
