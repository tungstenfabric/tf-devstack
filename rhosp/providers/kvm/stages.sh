#Stages for KVM deployment (it's part of run.sh)

source $my_dir/providers/kvm/virsh_functions


function kvm() {
    cd $my_dir/providers/kvm
    sudo ./01_create_env.sh
    wait_ssh ${mgmt_ip} ${ssh_private_key}
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        sudo ./02_collecting_node_information.sh
    else
        sudo touch ~/instackenv.json
    fi
}

function machines() {
    cd $my_dir
    scp -r $ssh_opts ~/rhosp-environment.sh ~/instackenv.json ~/tf-devstack stack@${mgmt_ip}:
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
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        ssh $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/01_extract_overcloud_images.sh
        #Checking vbmc statuses and fix 'down'
        local vm
        for vm in $(vbmc list -f value -c 'Domain name' -c Status | grep down | awk '{print $1}'); do
            vbmc start ${vm}
        done
        ssh $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/03_node_introspection.sh
        return
    fi

    # Predeployed nodes
    #
    #Copying keypair to the undercloud
    scp $ssh_opts $ssh_private_key $ssh_public_key stack@${mgmt_ip}:.ssh/
    #start overcloud VMs
    for domain in $(virsh list --name --all | grep $RHOSP_VERSION-overcloud-$DEPLOY_POSTFIX) ; do
        virsh start $domain
    done
    # copy prepare scripts
    local ip
    for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
        wait_ssh ${ip} ${ssh_private_key}
        scp $ssh_opts ~/rhosp-environment.sh ../common/collect_logs.sh ../common/common.sh \
        ../common/create_docker_config.sh ../common/jinja2_render.py \
        providers/common/* overcloud/03_setup_predeployed_nodes.sh stack@$ip:
        ssh $ssh_opts $SSH_USER@$ip mkdir -p ./files
        scp $ssh_opts ../common/files/docker_daemon.json.j2 $SSH_USER@$ip:files/
    done
    #parallel ssh
    local jobs=''
    for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
        ssh $ssh_opts stack@${ip} sudo ./03_setup_predeployed_nodes.sh &
        jobs+=" $!"
    done
    echo Parallel pre-instatallation overcloud nodes. pids: $jobs. Waiting...
    local res=0
    local i
    for i in $jobs ; do
        command wait $i || {
            echo "ERROR: job $i failed"
            res=1
        }
    done
    if [[ "${res}" == 1 ]]; then
        echo "errors appeared during overcloud nodes pre-installation."
        exit 1
    fi
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
