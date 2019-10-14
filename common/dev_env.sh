#!/bin/bash

set -o errexit

#TODO: should be broken for now

# get tf-dev-env
[ -d /root/tf-dev-env ] && sudo rm -rf /root/tf-dev-env
sudo cd /root && git clone https://github.com/tungstenfabric/tf-dev-env.git

# build all
sudo cd /root/tf-dev-env && AUTOBUILD=1 BUILD_DEV_ENV=1 ./startup.sh

# fix env variables
CONTAINER_REGISTRY="$(sudo docker inspect --format '{{(index .IPAM.Config 0).Gateway}}' bridge):6666"
CONTRAIL_CONTAINER_TAG="dev"
sudo git clone https://github.com/Juniper/$DEPLOYER_NAME.git $DEPLOYER_DIR
