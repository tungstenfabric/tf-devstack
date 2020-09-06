#Stages for KVM deployment (it's part of run.sh)

source $my_dir/providers/kvm/virsh_functions


function provisioning() {
    cd $my_dir/providers/kvm
    sudo -E ./01_create_env.sh
    wait_ssh ${mgmt_ip} ${ssh_private_key}
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        sudo ./02_collecting_node_information.sh
    fi
    if [[ -n "$ENABLE_TLS" ]] ; then
        wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
    fi
}

function machines() {
    cd $my_dir
    scp -r $ssh_opts ~/rhosp-environment.sh ~/instackenv.json $(dirname $my_dir) stack@${mgmt_ip}:
    cat <<EOF | ssh $ssh_opts stack@${mgmt_ip}
sudo ./tf-devstack/rhosp/undercloud/00_provision.sh
EOF
    if [[ -n "$ENABLE_TLS" ]] ; then
        scp -r $ssh_opts ~/rhosp-environment.sh $(dirname $my_dir) root@${ipa_mgmt_ip}:
        cat <<EOF | ssh $ssh_opts root@${ipa_mgmt_ip}
source ./rhosp-environment.sh
./tf-devstack/rhosp/providers/common/rhel_provisioning.sh
./tf-devstack/rhosp/ipa/freeipa_setup.sh
EOF
    fi
}

function undercloud() {
    cd $my_dir
    local otp=""
    if [[ -n "$ENABLE_TLS" ]] ; then
        otp=$(ssh $ssh_opts root@${ipa_mgmt_ip} cat ./undercloud_otp)
    fi
    cat <<EOF | ssh $ssh_opts stack@${mgmt_ip}
set -x
export OTP_PASSWORD=$otp
sudo /home/stack/tf-devstack/rhosp/undercloud/01_deploy_as_root.sh
/home/stack/tf-devstack/rhosp/undercloud/02_deploy_as_stack.sh
/home/stack/tf-devstack/rhosp/undercloud/${RHOSP_VERSION}_configure_registries_undercloud.sh
EOF
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
        if ! ssh $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/03_node_introspection.sh ; then
            echo "ERROR: failed ssh $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/03_node_introspection.sh"
            exit 1
        fi
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
        echo "ERROR: errors appeared during overcloud nodes pre-installation."
        exit 1
    fi
}

# TODO:
#   - move flavor into overcloud stage
#   - split containers preparation into openstack and contrail parts
#     and move openstack part into overcloud stage
#Overcloud stage w/o deploy for debug and customizations pruposes
function tf_no_deploy() {
    cd $my_dir
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/02_manage_overcloud_flavors.sh
    [[ $? -ne 0 ]] && exit 1
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/04_prepare_heat_templates.sh
    [[ $? -ne 0 ]] && exit 1
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/05_prepare_containers.sh
    [[ $? -ne 0 ]] && exit 1
}

#Overcloud stage
function tf() {
    cd $my_dir
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/02_manage_overcloud_flavors.sh
    [[ $? -ne 0 ]] && exit 1
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/04_prepare_heat_templates.sh
    [[ $? -ne 0 ]] && exit 1
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/05_prepare_containers.sh
    [[ $? -ne 0 ]] && exit 1
    ssh  $ssh_opts stack@${mgmt_ip} /home/stack/tf-devstack/rhosp/overcloud/06_deploy_overcloud.sh
    [[ $? -ne 0 ]] && exit 1
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    return 0
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}
