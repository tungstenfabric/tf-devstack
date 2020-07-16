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
SSL_ENABLE="$SSL_ENABLE"
EOF
  for key in ${!DEPLOYMENT_ENV[@]} ; do
    echo "${key}='${DEPLOYMENT_ENV[$key]}'" >> $file
  done
  echo "tf setup profile $file"
  cat ${file}
}

function run_stage() {
  if ! finished_stage $1 ; then
    $1 $2
  else
    echo "Skipping stage $1 because it's finished"
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

function is_active_() {
    echo "[is_active]"
    local status=`$(which juju) status`
    if [[ $status =~ "error" ]]; then
        echo "ERROR: Deployment has failed because juju state is error"
        echo "$status"
        exit 1
    fi  
    echo "[is_active]  passed if]"
    #[[ ! $(echo "$status" | egrep 'executing|blocked|waiting') ]]
    promres="$( echo "$status" | egrep 'executing|blocked|waiting' | wc -l )"
    echo "[is_active]  return $promres"
    return $promres
}

function wait_cmd_success_() {
  # silent mode = don't print output of input cmd for each attempt.
  echo "[wait_cmd_success_]"
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}
  local silent_cmd=${4:-1}

  local state_save=$(set +o)
  set +o xtrace
  set -o pipefail
  local i=0
  local is_active_res=1
  while [ $is_active_res -ne 0 ]; do
    echo "[wait_cmd_success_]  it $i"
    i=$((i + 1))
    is_active_res="$($cmd)"
    echo "[wait_cmd_success_]  is_active_res=$is_active_res" 
    if (( i > max )) ; then
      echo ""
      echo "ERROR: wait failed in $((i*10))s"
      eval "$cmd"
      eval "$state_save"
      echo "[wait_cmd_success_]  end return 1"
      return 1
    fi
    sleep $interval
  done
  echo "[wait_cmd_success_]  is_active_res=$is_active_res"
  echo "INFO: done in $((i*10))s"
  echo "[wait_cmd_success_]  end"
  eval "$state_save"
}

function wait() {
  echo "[wait]"
  local timeout=${WAIT_TIMEOUT:-1200}
  wait_cmd_success_ is_active_ 10 $((timeout/10))
  # collect additional env information about deployment for saving to profile after successful run
  echo "[wait]  collect_deployment_env"
  collect_deployment_env
  echo "[wait]  collect_deployment_env end"
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
