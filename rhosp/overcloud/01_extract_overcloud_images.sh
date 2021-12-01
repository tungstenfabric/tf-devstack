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

if [[ "$USE_PREDEPLOYED_NODES" != 'true' && "${ENABLE_RHEL_REGISTRATION,,}" != 'true' ]] ; then
  upload_commands=''
  for i in /etc/yum.repos.d/*.repo ; do echo $i; done
    upload_commands+= " --upload $i:$i"
  done
  if [ -n "$upload_commands" ] ; then
    echo "INFO: customize overcloud qcow: copy repos from undercloud to overcloud images: $upload_commands"
    virt-customize -a overcloud-full.qcow2 $upload_commands
  fi
fi

openstack overcloud image upload --image-path .
openstack image list

popd
