#!/bin/bash
# Adds MACHINES_TO_ADD machines to model for manual deployment

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# parameters
MACHINES_TO_ADD=${MACHINES_TO_ADD:-}

# add machines
if [ ! -z "$MACHINES_TO_ADD" ]; then
    for node in $MACHINES_TO_ADD ; do
        juju add-machine ssh:ubuntu@$node
    done
fi