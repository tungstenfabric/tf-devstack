#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh
source $my_dir/../../common/common.sh

# re-define flavors
for id in `openstack flavor list -f value -c ID` ; do openstack flavor delete $id ; done

openstack flavor create --id auto --ram 1000 --disk 29 --vcpus 2 baremetal
openstack flavor set --property "cpu_arch"="x86_64" \
                     --property "capabilities:boot_option"="local" \
                     --property "resources:CUSTOM_BAREMETAL=1" \
                     --property "resources:DISK_GB=0" \
                     --property "resources:MEMORY_MB=0" \
                     --property "resources:VCPU=0" \
                      baremetal
