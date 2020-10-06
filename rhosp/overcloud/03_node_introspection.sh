#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh
source $my_dir/../../common/common.sh

if [[ "${USE_PREDEPLOYED_NODES,,}" == true ]]; then
   echo "INFO: skip nodes introspection for pre-deployed nodes"
   exit 0
fi

# cleanup old nodes
for i in $(openstack baremetal node list -f value -c UUID) ; do
   openstack baremetal node delete $i || true
done

# import overcloud configuration
openstack overcloud node import ~/instackenv.json

# cleanup metadata only on Ceph nodes
for n in $(openstack baremetal node list -c Name -f value | grep ^ceph) ; do
   openstack baremetal node clean $n --clean-steps '[{"interface": "deploy", "step": "erase_devices_metadata"}]' --wait &
done
wait

openstack baremetal node list
openstack overcloud node introspect --all-manageable --provide

# TODO check every node
# Wait until nodes become manageable
for i in {1..3} ; do
   if ! openstack baremetal node list 2>&1 | grep -q 'manageable' ; then
      break
   fi
   sleep 5
done

openstack baremetal node list
