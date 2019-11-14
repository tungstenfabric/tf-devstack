#!/bin/bash

cd

if [[ `whoami` !=  'stack' ]]; then
   echo "This script must be run by user 'stack'" 
   exit 1
fi

if [ -f ~/env_desc.sh ]; then
   source ~/env_desc.sh
else
   echo "File ~/env_desc.sh not found"
   exit    
fi

if [ -f ~/stackrc ]; then
   source ~/stackrc
else
   echo "File /home/stack/stackrc not found"
   exit    
fi


mkdir ~/images
cd ~/images
for i in /usr/share/rhosp-director-images/overcloud-full-latest-13.0.tar /usr/share/rhosp-director-images/ironic-python-agent-latest-13.0.tar; do 
 tar -xvf $i; 
done

openstack overcloud image upload --image-path /home/stack/images/
openstack image list

