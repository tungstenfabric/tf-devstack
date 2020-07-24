#Stages for bmc deployment (it's part of run.sh)
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

function machines() {
    cd $my_dir
    sudo -E $my_dir/undercloud/00_provision.sh
}

function undercloud() {
    cd $my_dir
    sudo ./undercloud/01_deploy_as_root.sh
    ./undercloud/02_deploy_as_stack.sh
    ./undercloud/${RHOSP_VERSION}_configure_registries_undercloud.sh
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
    ./overcloud/06_deploy_overcloud.sh
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    return 0
}

function logs() {
    collect_deployment_log
}

function collect_deployment_env() {
    collect_overcloud_env
}
