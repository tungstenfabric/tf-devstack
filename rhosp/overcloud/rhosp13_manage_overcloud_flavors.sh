  openstack flavor create --id auto --ram 1000 --disk 29 --vcpus 2 baremetal
  openstack flavor set --property "cpu_arch"="x86_64" \
                       --property "capabilities:boot_option"="local" \
                       baremetal
