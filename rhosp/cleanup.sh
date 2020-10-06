#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export WORKSPACE=${WORKSPACE:-$(pwd)}

source $WORKSPACE/rhosp-environment.sh
source $my_dir/../common/common.sh
set +e
source $my_dir/providers/${PROVIDER}/cleanup.sh
rm -rf ~/.tf/.stages
