#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/../common/common.sh"
source "$my_dir/providers/common/common.sh"
source "$my_dir/providers/common/functions.sh"

if [ -n "$SSH_EXTRA_OPTIONS" ] ; then
  # add extra options for create_env.
  # for bmc setup it is needed for ssh proxy settings
  export ssh_opts="$ssh_opts $SSH_EXTRA_OPTIONS"
fi

$my_dir/providers/${PROVIDER}/create_env.sh
