#Stages for bmc deployment (it's part of run.sh)

function machines() {
    cd $my_dir
    scp -r $ssh_opts ~/rhosp-environment.sh ~/instackenv.json $(dirname $my_dir) stack@${mgmt_ip}:
    ssh $ssh_opts stack@${mgmt_ip} -- bash -c "cd; source ./rhosp-environment.sh; sudo -E ./tf-devstack/rhosp/undercloud/00_provision.sh"
}

function undercloud() {
    cd $my_dir
    ssh $ssh_opts stack@${mgmt_ip} sudo /home/stack/tf-devstack/rhosp/undercloud/01_deploy_as_root.sh
    ssh $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/undercloud/02_deploy_as_stack.sh
    patch_docker_configs
}

#Overcloud nodes provisioning
function overcloud() {
    cd $my_dir
    ssh $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/01_extract_overcloud_images.sh
    ssh $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/03_node_introspection.sh
}

#Overcloud stage
function tf() {
    cd $my_dir
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/02_manage_overcloud_flavors.sh
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/04_prepare_heat_templates.sh
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/05_prepare_containers.sh
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/06_deploy_overcloud.sh
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    return 0
}

function logs() {
    local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
    set +e
    set -x
    #Collecting undercloud logs
    create_log_dir
    local host_name=$(hostname -s)
    mkdir ${TF_LOG_DIR}/${host_name}
    collect_system_stats $host_name
    collect_stack_details ${TF_LOG_DIR}/${host_name}
    local servers_ip=$(openstack server list -c Networks -f value | awk -F '=' '{print $NF}')

    #Collecting overcloud logs
    for ip in $servers_ip; do
        scp $ssh_opts $my_dir/../common/collect_logs.sh heat-admin@$ip:
        ssh $ssh_opts heat-admin@$ip TF_LOG_DIR="/home/heat-admin/logs" ./collect_logs.sh create_log_dir
        ssh $ssh_opts heat-admin@$ip TF_LOG_DIR="/home/heat-admin/logs" ./collect_logs.sh collect_docker_logs
        ssh $ssh_opts heat-admin@$ip TF_LOG_DIR="/home/heat-admin/logs" ./collect_logs.sh collect_system_stats
        ssh $ssh_opts heat-admin@$ip TF_LOG_DIR="/home/heat-admin/logs" ./collect_logs.sh collect_contrail_logs
        host_name=$(ssh $ssh_opts heat-admin@$ip hostname -s)
        mkdir ${TF_LOG_DIR}/${host_name}
        scp -r $ssh_opts heat-admin@$ip:logs/* ${TF_LOG_DIR}/${host_name}/
    done

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs

    # Restore errexit state
    if [[ $errexit_state == 1 ]]; then
        set -e
    fi
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}
