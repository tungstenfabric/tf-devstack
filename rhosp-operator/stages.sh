
function machines() {
    $rhosp_dir/run.sh machines
    $operator_dir/run.sh machines
}

function operator_tf() {
    deploy_operator_file="deploy_operator.sh"

    export overcloud_node_ip=$overcloud_cont_prov_ip
    export cakey=$(echo "$SSL_CAKEY" | base64 -w 0)
    export cabundle=$(echo "$SSL_CACERT" | base64 -w 0)

    $my_dir/../common/jinja2_render.py < $my_dir/${deploy_operator_file}.j2 >${deploy_operator_file}
    sudo chmod 755 ${deploy_operator_file}

    scp $ssh_opts ${deploy_operator_file} $SSH_USER@$overcloud_ctrlcont_prov_ip:
    ssh $ssh_opts $SSH_USER@$overcloud_ctrlcont_prov_ip ./deploy_operator.sh
}

function tf() {
    $rhosp_dir/run.sh tf    
    operator_tf
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
    agent_nodes=$controller_nodes
    agent_nodes+=" $(get_ctlplane_ips controller)"
    agent_nodes+=" $(get_ctlplane_ips novacompute)"
    agent_nodes+=" $(get_ctlplane_ips contraildpdk)"
    agent_nodes+=" $(get_ctlplane_ips contrailsriov)"
    check_tf_active $SSH_USER_OVERCLOUD "$controller_nodes $agent_nodes"
    check_tf_services $SSH_USER_OVERCLOUD "$controller_nodes" "$agent_nodes"
}

function collect_deployment_env() {
    if is_after_stage 'wait' ; then
        collect_overcloud_env
    fi
}
