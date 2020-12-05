#!/bin/bash

# This script should be sourced after functions.sh wherever it's used

STAGE=$1
[[ -n $2 ]] && shift && OPTIONS="$@"

last_stage=''

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
  [ -z "$DEPLOYER_CONTAINER_REGISTRY" ] && DEPLOYER_CONTAINER_REGISTRY=$CONTAINER_REGISTRY || true
  [ -z "$CONTRAIL_CONTAINER_TAG" ] && CONTRAIL_CONTAINER_TAG='latest' || true
  [ -z "$CONTRAIL_DEPLOYER_CONTAINER_TAG" ] && CONTRAIL_DEPLOYER_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG || true
}

function save_tf_stack_profile() {
  local file=${1:-$TF_STACK_PROFILE}
  echo
  echo '[update tf stack configuration]'
  mkdir -p "$(dirname $file)"

  collect_deployment_env

  cat <<EOF > $file
DEPLOYER=${DEPLOYER}
CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG}
CONTRAIL_DEPLOYER_CONTAINER_TAG=${CONTRAIL_DEPLOYER_CONTAINER_TAG}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY}
DEPLOYER_CONTAINER_REGISTRY=${DEPLOYER_CONTAINER_REGISTRY}
ORCHESTRATOR=${ORCHESTRATOR}
OPENSTACK_VERSION="$OPENSTACK_VERSION"
CONTROLLER_NODES="$CONTROLLER_NODES"
AGENT_NODES="$AGENT_NODES"
SSL_ENABLE="$SSL_ENABLE"
LEGACY_ANALYTICS_ENABLE="$LEGACY_ANALYTICS_ENABLE"
HUGE_PAGES_1G=${HUGE_PAGES_1G}
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

function run_stage_force() {
  cleanup_stage $1
  run_stage $@
}

function finished_stage() {
  [ -e $TF_STAGES_DIR/$1 ]
}

function cleanup_stage() {
  local stage=${1:-'*'}
  rm -f $TF_STAGES_DIR/$stage
}

function wait() {
  sync_time
  local timeout=${WAIT_TIMEOUT:-1200}
  wait_cmd_success is_active 10 $((timeout/10))
}

function logs() {
  echo "INFO: collecting logs..."
  local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
  set +e

  create_log_dir
  collect_logs
  tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
  rm -rf $TF_LOG_DIR

  # Restore errexit state
  if [[ $errexit_state == 1 ]]; then
    set -e
  fi
}

function is_after_stage() {
  local stage=$1

  if [ -z "$last_stage" ]; then
    return 1
  fi
  stages_after=$(echo "${STAGES["all"]}" | sed "s/^.*$stage/$stage/")
  if [[ $stages_after == *"$last_stage"* ]] ; then
    return 0
  fi
  return 1
}

function run_stages() {
  [[ -z $STAGE ]] && STAGE="default"
  local stages=${STAGES[$STAGE]}
  local run_func=run_stage
  [[ -z $stages ]] && stages="$STAGE" && run_func=run_stage_force

  load_tf_devenv_profile

  echo "INFO: Applying stages ${stages[@]}"
  for stage in ${stages[@]} ; do
    echo "INFO: Running stage $stage at $(date)"
    $run_func $stage $OPTIONS
    last_stage=$stage
  done

  save_tf_stack_profile

  echo "INFO: Successful deployment $(date)"
  echo ""
}
