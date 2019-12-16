#!/bin/bash

# This script should be sourced after functions.sh wherever it's used

STAGE=$1
[[ -n $2 ]] && shift && OPTIONS="$@"

function load_tf_devenv_profile() {
  if [ -e "$TF_DEVENV_PROFILE" ] ; then
    echo
    echo '[load tf devenv configuration]'
    source "$TF_DEVENV_PROFILE"
    [ -n "$REGISTRY_IP" ] && CONTAINER_REGISTRY="${REGISTRY_IP}" && [ -n "$REGISTRY_PORT" ] && CONTAINER_REGISTRY+=":${REGISTRY_PORT}" || true
  else
    echo
    echo '[there is no tf devenv configuration to load]'
  fi
  # set to tungstenfabric if not set
  [ -z "$CONTAINER_REGISTRY" ] && CONTAINER_REGISTRY='tungstenfabric' || true
  [ -z "$CONTRAIL_CONTAINER_TAG" ] && CONTRAIL_CONTAINER_TAG='latest' || true
}

function save_tf_stack_profile() {
  local file=${1:-$TF_STACK_PROFILE}
  echo
  echo '[update tf stack configuration]'
  mkdir -p "$(dirname $file)"
  cat <<EOF > $file
DEPLOYER=${DEPLOYER}
CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY}
ORCHESTRATOR=${ORCHESTRATOR}
OPENSTACK_VERSION="$OPENSTACK_VERSION"
CONTROLLER_NODES="$CONTROLLER_NODES"
AGENT_NODES="$AGENT_NODES"
EOF
  for key in ${!DEPLOYMENT_ENV[@]} ; do
    echo "${key}=${DEPLOYMENT_ENV[$key]}" >> $file
  done
  echo "tf setup profile $file"
  cat ${file}
}

function run_stage() {
  if ! finished_stage $1 ; then
    $1 $2
  fi
  if [[ $1 != "wait" ]]; then
    mkdir -p $TF_STAGES_DIR
    touch $TF_STAGES_DIR/$1
  fi
}

function finished_stage() {
  [ -e $TF_STAGES_DIR/$1 ]
}

function cleanup_stage() {
  local stage=${1:-'*'}
  rm -f $TF_STAGES_DIR/$stage
}

function wait() {
  wait_cmd_success is_active 10 3000 0
  # collect additional env information about deployment for saving to profile after successful run 
  collect_deployment_env
}

function run_stages() {
  [[ -z $STAGE ]] && STAGE="default"
  stages=${STAGES[$STAGE]}
  [[ -z $stages ]] && stages="$STAGE"

  load_tf_devenv_profile

  echo "INFO: Applying stages ${stages[@]}"
  for stage in ${stages[@]} ; do
    echo "INFO: Running stage $stage at $(date)"
    run_stage $stage $OPTIONS
  done

  save_tf_stack_profile

  echo "INFO: Successful deployment $(date)"
}
