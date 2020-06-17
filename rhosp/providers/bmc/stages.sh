#Stages for bmc deployment (it's part of run.sh)
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

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
    ./overcloud/01_extract_overcloud_images.sh
    ./overcloud/03_node_introspection.sh
}

#Overcloud stage
function tf() {
    cd $my_dir
    ./overcloud/02_manage_overcloud_flavors.sh
    ./overcloud/04_prepare_heat_templates.sh
    ./overcloud/05_prepare_containers.sh
    SSH_USER=heat-admin ./overcloud/06_deploy_overcloud.sh
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    return 0
}

function logs() {
    add_overcloud_user
    collect_deployment_log
}

function collect_deployment_env() {
    collect_overcloud_env
    DEPLOYMENT_ENV['AUTH_URL']="${os_auth_internal_api_url}"
    DEPLOYMENT_ENV['AUTH_PASSWORD']="${OS_PASSWORD}"
    DEPLOYMENT_ENV['AUTH_REGION']="${OS_REGION_NAME}"
    DEPLOYMENT_ENV['AUTH_PORT']="35357"
}
