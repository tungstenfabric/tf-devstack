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

function collect_deployment_env() {
    # no additinal info is needed
    :
}
