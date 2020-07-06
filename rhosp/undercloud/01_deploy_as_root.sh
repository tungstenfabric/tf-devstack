#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ~/rhosp-environment.sh

#Specific part of deployment
source $my_dir/${RHEL_VERSION}_deploy_as_root.sh
