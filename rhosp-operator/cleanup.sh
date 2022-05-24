#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export WORKSPACE=${WORKSPACE:-$(pwd)}

rhosp_dir=$my_dir/../rhosp
operator_dir=$my_dir/../operator

source $WORKSPACE/rhosp-environment.sh
source $my_dir/../common/common.sh
source $my_dir/providers/common/common.sh
set +e
ssh $ssh_opts $SSH_USER@$overcloud_ctrlcont_prov_ip $operator_dir/cleanup.sh
source $rhosp_dir/providers/${PROVIDER}/cleanup.sh
rm -rf ~/.tf/.stages
