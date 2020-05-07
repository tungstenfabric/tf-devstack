#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [ -f ~/rhosp-environment.sh ]; then
   source ~/rhosp-environment.sh
else
   echo "File ~/rhosp-environment.sh not found"
   exit
fi

if [ -f ~/stackrc ]; then
   source ~/stackrc
else
   echo "File ~/stackrc not found"
   exit
fi

# re-define flavors
for id in `openstack flavor list -f value -c ID` ; do openstack flavor delete $id ; done

#Specific part of deployment
source $my_dir/${RHOSP_VERSION}_manage_overcloud_flavors.sh

