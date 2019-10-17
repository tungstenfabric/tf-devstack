#!/bin/bash -e

function fetch_deployer() {
    sudo_cmd=""
    [ "$(whoami)" != "root" ] && sudo_cmd="sudo"
    $sudo_cmd rm -rf "$WORKSPACE/$DEPLOYER_DIR"
    $sudo_cmd docker create --name $DEPLOYER_IMAGE $CONTAINER_REGISTRY/$DEPLOYER_IMAGE:$CONTRAIL_CONTAINER_TAG
    $sudo_cmd docker cp $DEPLOYER_IMAGE:$DEPLOYER_DIR $WORKSPACE
    $sudo_cmd docker rm -fv $DEPLOYER_IMAGE
    $sudo_cmd chown -R $USER "$WORKSPACE/$DEPLOYER_DIR"
}
