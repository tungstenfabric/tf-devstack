
function machines() {
    $rhosp_dir/run.sh machines

    $my_dir/run_operator_machines.sh
}

function tf() {
    $rhosp_dir/run.sh tf
    $my_dir/run_operator_tf.sh
}

function logs() {
    collect_deployment_log
}

function is_active() {
    # Services to check in wait stage
    CONTROLLER_SERVICES['config-database']=""
    CONTROLLER_SERVICES['config']+="dnsmasq "
    CONTROLLER_SERVICES['_']+="rabbitmq stunnel zookeeper "
    if [[ "${CNI}" == "calico" ]]; then
        AGENT_SERVICES['vrouter']=""
    fi

    local agent_nodes=""
    local controller_nodes=""
    controller_nodes="$(get_ctlplane_ips contrailcontroller)"
    agent_nodes="$(get_ctlplane_ips novacompute)"
    agent_nodes+=" $(get_ctlplane_ips contraildpdk)"
    agent_nodes+=" $(get_ctlplane_ips contrailsriov)"
    if [[ -z $agent_nodes ]] ; then
        # AIO mode
        agent_nodes="$(get_ctlplane_ips controller)"
    fi
    agent_nodes+=" $controller_nodes"
    local k8s_node=$(echo $overcloud_ctrlcont_prov_ip | cut -d, -f1)
    # waiting for operator part to be ready
    ssh $ssh_opts $SSH_USER@$k8s_node ./tf-devstack/operator/run.sh wait
    check_tf_active $SSH_USER_OVERCLOUD "$controller_nodes $agent_nodes"
    check_tf_services $SSH_USER_OVERCLOUD "$controller_nodes" "$agent_nodes"
}

function collect_deployment_env() {
    if is_after_stage 'wait' ; then
        collect_overcloud_env
    fi
}
