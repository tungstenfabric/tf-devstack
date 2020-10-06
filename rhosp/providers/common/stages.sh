
function machines() {
    cd $my_dir
    sudo -E ./undercloud/00_provision.sh
    if [[ -n "$ENABLE_TLS" ]] ; then
        cat <<EOF | ssh $ssh_opts root@${ipa_mgmt_ip}
set -e
cd
source rhosp-environment.sh
./tf-devstack/rhosp/providers/common/rhel_provisioning.sh
./tf-devstack/rhosp/ipa/freeipa_setup.sh
EOF
        scp $ssh_opts root@${ipa_mgmt_ip}:./undercloud_otp ~/
    fi
}

function undercloud() {
    cd $my_dir
    if [[ -n "$ENABLE_TLS" ]] ; then
        export OTP_PASSWORD=$(cat ~/undercloud_otp)
    fi

    sudo ./undercloud/01_deploy_as_root.sh
    ./undercloud/02_deploy_as_stack.sh
    ./undercloud/${RHOSP_VERSION}_configure_registries_undercloud.sh
}

function _overcloud_preprovisioned_nodes()
{
    if [[ "$RHOSP_VERSION" == 'rhosp13' ]] ; then
        ./overcloud/03_setup_predeployed_nodes_access.sh
    fi
    cd
    local jobs=""
    local ip
    for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
        local tf_devstack_path=$(dirname $my_dir)
        scp -r rhosp-environment.sh $tf_devstack_path $SSH_USER@$ip:
        ssh $ssh_opts $SSH_USER@$ip ./$(basename $tf_devstack_path)/overcloud/03_setup_predeployed_nodes.sh &
        jobs+=" $!"
    done
    echo Parallel pre-installation overcloud nodes. pids: $jobs. Waiting...
    local res=0
    local i
    for i in $jobs ; do
        command wait $i || res=1
    done
    if [[ "${res}" == 1 ]]; then
        echo errors appeared during overcloud nodes pre-installation. Exiting
        exit 1
    fi
}

function overcloud() {
    cd $my_dir
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        ./overcloud/01_extract_overcloud_images.sh
        ./overcloud/03_node_introspection.sh
    else
        _overcloud_preprovisioned_nodes
    fi
}

# TODO:
#   - move flavor into overcloud stage
#   - split containers preparation into openstack and contrail parts
#     and move openstack part into overcloud stage
#Overcloud stage w/o deploy for debug and customizations pruposes
function tf_no_deploy() {
    cd $my_dir
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        ./overcloud/02_manage_overcloud_flavors.sh
    fi
    ./overcloud/04_prepare_heat_templates.sh
    ./overcloud/05_prepare_containers.sh
}

function tf() {
    cd $my_dir
    tf_no_deploy
    ./overcloud/06_deploy_overcloud.sh
    if [[ "${ENABLE_NETWORK_ISOLATION,,}" == true ]]; then
      add_vlan_interface ${internal_vlan} ${internal_interface} ${internal_ip_addr} ${internal_net_mask}
      add_vlan_interface ${external_vlan} ${external_interface} ${external_ip_addr} ${external_net_mask}
    fi
}

function logs() {
    collect_deployment_log
}

function is_active() {
    return 0
}

function collect_deployment_env() {
    collect_overcloud_env
}
