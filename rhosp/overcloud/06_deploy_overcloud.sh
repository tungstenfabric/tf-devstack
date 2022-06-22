#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh
source $my_dir/../../common/common.sh
source $my_dir/../../common/functions.sh
source $my_dir/../providers/common/functions.sh
source $my_dir/../providers/common/common.sh

#Specific part of deployment
echo "INFO: source file $my_dir/${RHOSP_MAJOR_VERSION}_deploy_overcloud.sh"
source $my_dir/${RHOSP_MAJOR_VERSION}_deploy_overcloud.sh

status=$(openstack stack show -f json overcloud | jq ".stack_status")
if [[ ! "$status" =~ 'COMPLETE' || -z "$status" ]] ; then
  echo "ERROR: failed to deploy overcloud: status=$status"
  exit -1
fi
