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

function wait_cmd_success() {
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-60}
  local i=0
  while ! $cmd 2>/dev/null; do
      printf "."
      i=$((i + 1))
      if (( i > max )) ; then
        return 1
      fi
      sleep $interval
  done
  return 0
}

function wait_nic_up() {
  local nic=$1
  printf "INFO: wait for $nic is up"
  wait_cmd_success "nic_has_ip $nic" || { echo -e "\nERROR: $nic is not up" && return 1; }
  echo -e "\nINFO: $nic is up"
}