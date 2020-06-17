#Stages for VEXX deployment (it's part of run.sh)

export CONFIGURE_DOCKER_LIVERESTORE='false'

ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no"

function machines() {
    cd $my_dir
    sudo -E bash -c "source /home/$user/rhosp-environment.sh; $my_dir/undercloud/00_provision.sh"
}

function undercloud() {
    cd $my_dir
    sudo ./undercloud/01_deploy_as_root.sh
    ./undercloud/02_deploy_as_stack.sh
    patch_docker_configs
}

#Overcloud nodes provisioning
function overcloud() {
    cd $my_dir
    ./overcloud/03_setup_predeployed_nodes_access.sh
    local jobs=""
    local res=0
    for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
        scp $ssh_opts ~/rhosp-environment.sh  ../common/collect_logs.sh \
            ../common/create_docker_config.sh ../common/jinja2_render.py \
            providers/common/* overcloud/03_setup_predeployed_nodes.sh $SSH_USER@$ip:
        ssh $ssh_opts $SSH_USER@$ip mkdir -p ./files
        scp $ssh_opts ../common/files/docker_daemon.json.j2 $SSH_USER@$ip:files/
        ssh $ssh_opts $SSH_USER@$ip sudo ./03_setup_predeployed_nodes.sh &
        jobs+=" $!"
    done
    echo Parallel pre-installation overcloud nodes. pids: $jobs. Waiting...
    local i
    for i in $jobs ; do
        command wait $i || res=1
    done
    if [[ "${res}" == 1 ]]; then
        echo errors appeared during overcloud nodes pre-installation. Exiting
        exit 1
    fi
}

#Overcloud stage
function tf() {
    cd $my_dir
    ./overcloud/04_prepare_heat_templates.sh
    ./overcloud/05_prepare_containers.sh
    ./overcloud/06_deploy_overcloud.sh
}

function logs() {
    collect_deployment_log
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    return 0
}

function collect_deployment_env() {
    collect_overcloud_env $SSH_USER
    DEPLOYMENT_ENV['AUTH_URL']="${os_auth_internal_api_url}"
    DEPLOYMENT_ENV['AUTH_PASSWORD']="${OS_PASSWORD}"
    DEPLOYMENT_ENV['AUTH_REGION']="${OS_REGION_NAME}"
    DEPLOYMENT_ENV['AUTH_PORT']="35357"
}
