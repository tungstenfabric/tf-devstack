#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

$my_dir/run.sh provisioning

