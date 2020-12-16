
function _run()
{
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
    # dirty hack - somehow started vbmc port becomes down at time of this stage
    echo "INFO: vbmc ports status"
    sudo vbmc --no-daemon list || true
    echo "INFO: start all vbmc ports"
    sudo vbmc --no-daemon start $(vbmc --no-daemon list -c 'Domain name' -f value) || true
    _run overcloud
}

function tf_no_deploy() {
    _run tf_no_deploy
}

function tf() {
    _run tf_no_time
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
