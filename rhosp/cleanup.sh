#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source "$my_dir/../common/common.sh"

source $my_dir/providers/${PROVIDER}/cleanup.sh
