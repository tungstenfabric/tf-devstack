#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source stackrc

mkdir -p images
pushd images
for i in /usr/share/rhosp-director-images/overcloud-full-latest.tar /usr/share/rhosp-director-images/ironic-python-agent-latest.tar; do
  tar -xvf $i;
done
popd

openstack overcloud image upload --image-path $HOME/images
openstack image list
