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

function create_flavor() {
  local name=$1
  local profile=${2:-''}
  openstack flavor create --id auto --ram 1000 --disk 29 --vcpus 2 $name
  openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" $name
  if [[ -n "$profile" ]] ; then
    openstack flavor set --property "capabilities:profile"="${profile}" $name
  else
    echo "Skip flavor profile propery set for $name"
  fi
}

create_flavor 'control' 'controller'
create_flavor 'compute' 'compute'
create_flavor 'contrail-controller' 'contrail-controller'

