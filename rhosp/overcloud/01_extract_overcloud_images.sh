#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh
source $my_dir/../../common/common.sh
  
mkdir -p images
pushd images

for i in /usr/share/rhosp-director-images/overcloud-full-latest.tar /usr/share/rhosp-director-images/ironic-python-agent-latest.tar; do
  tar -xvf $i
done

openstack overcloud image upload --image-path .
openstack image list

popd
