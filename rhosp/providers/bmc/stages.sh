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
    ssh  $ssh_opts stack@${mgmt_ip} "export PATH=\$PATH:/usr/sbin; /home/stack/tf-devstack/rhosp/providers/bmc/collect_node_logs.sh"
    scp -r $ssh_opts stack@${mgmt_ip}:logs.tgz ${TF_LOG_DIR}/ || /bin/true
}

function collect_deployment_env() {
    ssh  $ssh_opts stack@${mgmt_ip} "/home/stack/tf-devstack/rhosp/providers/bmc/collect_deployment_env.sh"
    eval $(ssh $ssh_opts stack@${mgmt_ip} "cat /home/stack/deployment.env")
    DEPLOYMENT_ENV['AUTH_URL']="${os_auth_internal_api_url}"
    DEPLOYMENT_ENV['AUTH_PASSWORD']="${OS_PASSWORD}"
    DEPLOYMENT_ENV['AUTH_REGION']="${OS_REGION_NAME}"
    DEPLOYMENT_ENV['AUTH_PORT']="35357"
}
