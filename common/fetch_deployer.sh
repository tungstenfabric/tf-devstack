#!/bin/bash

set -o errexit

sudo rm -rf $DEPLOYER_DIR
sudo docker run --name $DEPLOYER_IMAGE -d --rm --entrypoint "/usr/bin/tail" $CONTRAIL_REGISTRY/$DEPLOYER_IMAGE:$CONTRAIL_VERSION -f /dev/null
sudo docker cp $DEPLOYER_IMAGE:$DEPLOYER_DIR .
sudo docker stop $DEPLOYER_IMAGE
