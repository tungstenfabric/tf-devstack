
function _preset_undercloud_prov_net() {
    if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
    # WA for TLS
    #   To avoid error:
    #     ipa-getkeytab -s rhosp16-ipa-20.dev.localdomain -p nova/rhosp16-undercloud-20.dev.localdomain -k /etc/novajoin/krb5.keytab
    #     Failed to add key to the keytab
    sudo mkdir -p /etc/novajoin
    #   To avoid error with domain resolving 
    cat << EOF | sudo tee /etc/resolv.conf 
    # Generated by tf-devstack
    search ${domain}
    nameserver $ipa_prov_ip
EOF
    fi

    # Up eth1 with address in  prov network.
    # undercloud install connects to IPA before it setups br-ctlplane 
    cat << EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-eth1
    # This file is autogenerated by tf-devstack
    DEVICE=eth1
    ONBOOT=no
    HOTPLUG=no
    NM_CONTROLLED=no
    BOOTPROTO=none
    IPADDR=$prov_ip
    PREFIX=$prov_subnet_len
EOF
    sudo modprobe ipv6 || true
    sudo ifdown eth1 || true
    sudo ifup eth1
}

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
    declare -A jobs_descr
    local ip
    for ip in ${overcloud_cont_prov_ip//,/ } ${overcloud_compute_prov_ip//,/ } ${overcloud_ctrlcont_prov_ip//,/ } ; do
        _overcloud_setup_overcloud_node $ip &
        jobs_descr[$!]="_overcloud_setup_overcloud_node $ip"
        jobs+=" $!"
    done
    echo "Parallel pre-installation overcloud nodes. pids: $jobs. Waiting..."
    local res=0
    local i
    for i in $jobs ; do
        command wait $i || {
            echo "ERROR: failed ${jobs_descr[$i]}"
            res=1
        }
    done
    [[ "${res}" == 0 ]] || exit 1
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
    _preset_undercloud_prov_net
    $my_dir/providers/common/rhel_provisioning.sh &
    local jobs="$!"
    if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
        _setup_ipa &
        command wait $! || {
            echo "ERROR: failed to setup ipa"
            exit 1
        }
        scp $ssh_opts $SSH_USER@${ipa_mgmt_ip}:./undercloud_otp ~/
    fi
    command wait $jobs || {
        echo "ERROR: failed to provision undercloud"
        exit 1
    }
    # deploy undercloud & enroll overcloud nodes
    declare -A jobs_descr
    _undercloud &
    jobs="$!"
    jobs_descr[$!]="_undercloud"
    _overcloud_preprovisioned_nodes &
    jobs+=" $!"
    jobs_descr[$!]="_overcloud_preprovisioned_nodes"
    local i
    local res=0
    for i in $jobs ; do
        command wait $i || {
            echo "ERROR: failed ${jobs_descr[$i]}"
            res=1
        }
    done
    [[ "${res}" == 0 ]] || exit 1
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
