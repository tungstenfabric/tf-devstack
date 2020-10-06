#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh

#Specific part
source $my_dir/${RHOSP_VERSION}_prepare_containers.sh
