#!/bin/bash -e

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"
source "$my_dir/../../../common/common.sh"
source "$my_dir/../../../common/functions.sh"
source $my_dir/definitions

sync_time core $(oc get nodes -o wide | awk '/master|worker/{print $6}' | tr '\n' ' ')

