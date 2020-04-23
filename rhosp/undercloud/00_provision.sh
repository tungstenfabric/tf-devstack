#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

$my_dir/../providers/common/rhel_provisioning.sh
