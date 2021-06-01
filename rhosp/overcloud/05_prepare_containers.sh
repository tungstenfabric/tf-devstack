#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh
source $my_dir/../../common/common.sh

#Specific part
echo "INFO: source file $my_dir/${RHOSP_MAJOR_VERSION}_prepare_containers.sh"
source $my_dir/${RHOSP_MAJOR_VERSION}_prepare_containers.sh
