
function _run()
{
    source $WORKSPACE/rhosp-environment.sh
    cat <<EOF | ssh $ssh_opts stack@${instance_ip}
source /etc/profile
source rhosp-environment.sh
./tf-devstack/rhosp/run.sh $@
EOF
}

function machines() {
    _run machines
}

function undercloud() {
    _run undercloud
}

function overcloud() {
    _run overcloud
}

function tf_no_deploy() {
    _run tf_no_deploy
}

function tf() {
    _run tf
}

function is_active() {
    _run is_active
}

function logs() {
    _run logs
}

function collect_deployment_env() {
    _run collect_deployment_env
}

trap on_exit EXIT

function on_exit() {
  # rm tf-devstack profile on kvm node,
  # as real profile is on undercloud
  [ -n "$TF_STACK_PROFILE" ] && [ -e $TF_STACK_PROFILE ] && rm -f $TF_STACK_PROFILE || true
  echo "DEBUG: remove $TF_STACK_PROFILE on kvm node"
}
