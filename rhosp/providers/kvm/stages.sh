
function provisioning() {
    cd $WORKSPACE
    $my_dir/providers/kvm/01_create_env.sh
    wait_ssh ${mgmt_ip} ${ssh_private_key}
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        $my_dir/providers/kvm/02_collecting_node_information.sh
    fi
    scp $ssh_opts ${ssh_private_key} ${ssh_public_key} root@${mgmt_ip}:./.ssh/
    scp $ssh_opts ${ssh_private_key} ${ssh_public_key} stack@${mgmt_ip}:./.ssh/
    scp -r $ssh_opts rhosp-environment.sh instackenv.json $(dirname $my_dir) stack@${mgmt_ip}:
    if [[ -n "$ENABLE_TLS" ]] ; then
        wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
        scp -r $ssh_opts rhosp-environment.sh $(dirname $my_dir) root@${ipa_mgmt_ip}:
    fi
}

function _run()
{
    ssh $ssh_opts stack@${mgmt_ip} ./tf-devstack/rhosp/run.sh $@
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
    ;
}
