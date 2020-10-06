#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh

# re-define flavors
for id in `openstack flavor list -f value -c ID` ; do openstack flavor delete $id ; done

#Specific part of deployment
source $my_dir/${RHOSP_VERSION}_manage_overcloud_flavors.sh

