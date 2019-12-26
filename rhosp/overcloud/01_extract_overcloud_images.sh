#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ `whoami` !=  'stack' ]]; then
   echo "This script must be run by user 'stack'"
   exit 1
fi

if [ -f $my_dir/../config/env.sh ]; then
   source $my_dir/../config/env.sh
else
   echo "File $my_dir/../config/env.sh not found"
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

