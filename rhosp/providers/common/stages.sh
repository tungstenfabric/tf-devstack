
function _setup_ipa() {
    local fqdn=$(hostname -f)
    cat <<EOF | ssh $ssh_opts $SSH_USER@${ipa_mgmt_ip}
./tf-devstack/rhosp/providers/common/rhel_provisioning.sh
export UndercloudFQDN=$fqdn
export AdminPassword=$ADMIN_PASSWORD
export FreeIPAIP=$ipa_prov_ip
export FreeIPAIPSubnet=$prov_subnet_len
./tf-devstack/rhosp/ipa/freeipa_setup.sh
EOF
}

function _enroll_ipa_overcloud_node() {
    local ip=$1
    local fqdn=$(ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip hostname -f)
    cat <<EOF | ssh $ssh_opts $SSH_USER@${ipa_mgmt_ip} >${fqdn}.otp
sudo novajoin-ipa-setup \
    --principal admin \
    --password "$ADMIN_PASSWORD" \
    --server \$(hostname -f) \
    --realm ${domain^^} \
    --domain ${domain} \
    --hostname ${fqdn} \
    --precreate
EOF
    scp $ssh_opts ${fqdn}.otp $SSH_USER_OVERCLOUD@$ip:
    cat <<EOF | ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip >${fqdn}.otp
sudo hostnamectl set-hostname $fqdn
sudo ipa-client-install --verbose -U -w $(cat ${fqdn}.otp) --hostname $fqdn --domain=$domain
EOF
}

function _overcloud_setup_overcloud_node() {
    local ip=$1
    local tf_devstack_path=$(dirname $my_dir)
    scp $ssh_opts -r rhosp-environment.sh $tf_devstack_path $SSH_USER_OVERCLOUD@$ip:
    ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip ./$(basename $tf_devstack_path)/rhosp/overcloud/03_setup_predeployed_nodes.sh
    if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
        _enroll_ipa_overcloud_node $ip
    fi
}

function _overcloud_preprovisioned_nodes()
{
    cd
    local jobs=""
    local ip
    for ip in ${overcloud_cont_prov_ip//,/ } ${overcloud_compute_prov_ip//,/ } ${overcloud_ctrlcont_prov_ip//,/ } ; do
        _overcloud_setup_overcloud_node $ip &
        jobs+=" $!"
    done
    echo "Parallel pre-installation overcloud nodes. pids: $jobs. Waiting..."
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

function _undercloud() {
    if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
        export OTP_PASSWORD=$(cat ~/undercloud_otp)
    fi
    $my_dir/undercloud/undercloud_deploy.sh
}

function _overcloud() {
    cd $my_dir
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        ./overcloud/01_extract_overcloud_images.sh
        ./overcloud/03_node_introspection.sh
    else
        # this script uses openstack mistral and cannot be run at machines step
        ./overcloud/03_setup_predeployed_nodes_access.sh
    fi
}

function machines() {
    # provision
    $my_dir/providers/common/rhel_provisioning.sh &
    local jobs="$!"
    if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
        _setup_ipa &
        wait $!
        scp $ssh_opts $SSH_USER@${ipa_mgmt_ip}:./undercloud_otp ~/
    fi
    wait $jobs
    # deploy undercloud & enroll overcloud nodes
    _undercloud &
    jobs="$!"
    _overcloud_preprovisioned_nodes &
    jobs+=" $!"
    local j
    for j in $jobs ; do
        wait $j
    done
    # prepare overcloud images and introspection
    _overcloud
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
}

function logs() {
    collect_deployment_log
}

function is_active() {
    return 0
}

function collect_deployment_env() {
    if is_after_stage 'wait' ; then
        collect_overcloud_env
    fi
}
