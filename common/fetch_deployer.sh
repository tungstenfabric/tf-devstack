#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"

([ -z $CONTRAIL_REGISTRY ] || [ -z $CONTRAIL_VERSION ] ) && echo "Please set contrail registry and version parameters"

sudo rm -rf $DEPLOYER_DIR
sudo docker run --name $DEPLOYER_IMAGE -d --rm --entrypoint "/usr/bin/tail" $CONTRAIL_REGISTRY/$DEPLOYER_IMAGE:$CONTRAIL_VERSION -f /dev/null
sudo docker cp $DEPLOYER_IMAGE:$DEPLOYER_DIR .
sudo docker stop $DEPLOYER_IMAGE