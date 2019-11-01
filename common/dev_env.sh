#!/bin/bash

set -o errexit

#TODO: should be broken for now

DEPLOYER_NAME=contrail-container-buider

# get tf-dev-env
[ -d $WORKSPACE/tf-dev-env ] && sudo rm -rf $WORKSPACE/tf-dev-env
sudo cd $WORKSPACE && git clone --depth 1 --single-branch https://github.com/tungstenfabric/tf-dev-env.git

# build all
sudo cd $WORKSPACE/tf-dev-env && AUTOBUILD=1 BUILD_DEV_ENV=1 ./startup.sh

# fix env variables
# TODO: they must be returned to caller
CONTAINER_REGISTRY="$(sudo docker inspect --format '{{(index .IPAM.Config 0).Gateway}}' bridge):6666"
CONTRAIL_CONTAINER_TAG="dev"
sudo git clone --depth 1 --single-branch https://github.com/Juniper/$DEPLOYER_NAME.git $DEPLOYER_DIR
