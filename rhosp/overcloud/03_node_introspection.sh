#!/bin/bash

cd
if [ -f ~/stackrc ]; then
   source ~/stackrc
else
   echo "File ~/stackrc not found"
   exit
fi

if [ -f ~/instackenv.json ]; then
   echo Using ~/instackenv.json
else
   echo "File ~/instackenv.json not found"
   exit
fi


# cleanup old nodes
for i in $(openstack baremetal node list -f value -c UUID) ; do
  openstack baremetal node delete $i || true
done

# import overcloud configuration
openstack overcloud node import ~/instackenv.json
openstack baremetal node list
for i in {1..3} ; do
   openstack overcloud node introspect --all-manageable --provide
   if ! openstack baremetal node list 2>&1 | grep -q 'manageable' ; then
      break
   fi
   sleep 5
done

openstack baremetal node list

