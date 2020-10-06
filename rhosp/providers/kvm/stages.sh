
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
    return 0
}

function logs() {
    _run logs
}

function collect_deployment_env() {
    :
}
