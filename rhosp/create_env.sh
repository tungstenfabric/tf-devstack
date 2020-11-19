#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/../common/common.sh"
source "$my_dir/providers/common/common.sh"
source "$my_dir/providers/common/functions.sh"

$my_dir/providers/${PROVIDER}/create_env.sh
