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


mkdir ~/images
cd ~/images
for i in /usr/share/rhosp-director-images/overcloud-full-latest.tar /usr/share/rhosp-director-images/ironic-python-agent-latest.tar; do
  tar -xvf $i;
done

openstack overcloud image upload --image-path ~/images/
openstack image list
