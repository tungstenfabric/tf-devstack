#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export WORKSPACE=${WORKSPACE:-$(pwd)}
export PROVIDER=${PROVIDER:-}
[ -n "$PROVIDER" ] || { echo "ERROR: PROVIDER is not set"; exit -1; }

source "$my_dir/providers/common/functions.sh"
source $my_dir/providers/${PROVIDER}/stages.sh
provisioning
