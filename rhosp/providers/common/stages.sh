
function _predeploy_undercloud() {
    # ssh config to do not check host keys and avoid garbadge in known hosts files
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cat <<EOF >~/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF
    chmod 644 ~/.ssh/config

    # Overwrite ifcfg as  br-ctlplane will take IP 
    local local_mtu=`/sbin/ip link show $undercloud_local_interface | grep -o "mtu.*" | awk '{print $2}'`
    cat << EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-$undercloud_local_interface
# This file is autogenerated by tf-devstack
DEVICE=$undercloud_local_interface
MTU=$local_mtu
ONBOOT=no
HOTPLUG=no
NM_CONTROLLED=no
BOOTPROTO=none
IPADDR=$prov_ip
PREFIX=$prov_subnet_len
EOF

    # Up eth1 with address in  prov network.
    # undercloud install connects to IPA before it setups br-ctlplane
    # (dont use ifup because in rhel8 it is not work properly w/o NM)
    sudo ip link set up dev $undercloud_local_interface
    sudo ip addr replace ${prov_ip}/${prov_subnet_len} dev $undercloud_local_interface
    sudo ip addr show
}

function _setup_ipa() {
    local fqdn=$(hostname -f)
    cat <<EOF | ssh $ssh_opts $SSH_USER@${ipa_mgmt_ip}
[[ "$DEBUG" == true ]] && set -x
./tf-devstack/rhosp/providers/common/rhel_provisioning.sh
export UndercloudFQDN=$fqdn
export AdminPassword=$ADMIN_PASSWORD
export FreeIPAIP=$ipa_prov_ip
export FreeIPAIPSubnet=$prov_subnet_len
./tf-devstack/rhosp/ipa/freeipa_setup.sh
EOF
}

function _overcloud_setup_overcloud_node() {
    local ip=$1
    local tf_devstack_path=$(dirname $my_dir)
    scp $ssh_opts -r rhosp-environment.sh $tf_devstack_path $SSH_USER_OVERCLOUD@$ip:
    ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip ./$(basename $tf_devstack_path)/rhosp/overcloud/03_setup_predeployed_nodes.sh
}

function _overcloud_preprovisioned_nodes()
{
    local jobs=""    
    declare -A jobs_descr
    $my_dir/overcloud/03_setup_predeployed_nodes_access.sh &
    jobs_descr[$!]="03_setup_predeployed_nodes_access"
    jobs+=" $!"
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
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        $my_dir/overcloud/01_extract_overcloud_images.sh
        $my_dir/overcloud/03_node_introspection.sh
    else
        if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
            echo "$ADMIN_PASSWORD" | kinit admin
            local net
            for net in ${!RHOSP_NETWORKS[@]} ; do
                ipa dnszone-find "${net}.${domain}" || ipa dnszone-add "${net}.${domain}"
            done
        fi
        # this script uses openstack mistral and cannot be run before undercloud deploy
        _overcloud_preprovisioned_nodes
        if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
            # this should be after enrolloing nodes (_overcloud_preprovisioned_nodes)
            echo "$ADMIN_PASSWORD" | kinit admin
            local net
            local service
            local i
            for net in ${!RHOSP_VIP_NETWORKS[@]} ; do
                for service in ${RHOSP_VIP_NETWORKS[$net]} ; do
                    for i in ${overcloud_cont_instance//,/ } ; do
                        add_node_to_ipa "overcloud" "${net}.${domain}" "$fixed_vip" "$service" "${i}.${domain}"
                    done
                done
            done
            # vip public
            for i in ${overcloud_cont_instance//,/ } ; do
                add_node_to_ipa "overcloud" "$domain" "$fixed_vip" "haproxy" "${i}.${domain}"
            done
        fi
    fi
}

function machines() {
    cd
    _predeploy_undercloud
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
    _undercloud
    _overcloud
}

# TODO:
#   - move flavor into overcloud stage
#   - split containers preparation into openstack and contrail parts
#     and move openstack part into overcloud stage
#Overcloud stage w/o deploy for debug and customizations pruposes
function tf_no_deploy() {
    cd
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        $my_dir/overcloud/02_manage_overcloud_flavors.sh
    fi
    $my_dir/overcloud/04_prepare_heat_templates.sh
    $my_dir/overcloud/05_prepare_containers.sh
}

function tf() {
    cd
    tf_no_deploy
    $my_dir/overcloud/06_deploy_overcloud.sh
}

function logs() {
    collect_deployment_log
}

function is_active() {
    local nodes="$(get_ctlplane_ips contrailcontroller)"
    if [ -z "$nodes" ] ; then
        # AIO
        nodes="$(get_ctlplane_ips controller)"
    fi
    nodes+=" $(get_ctlplane_ips novacompute)"
    nodes+=" $(get_ctlplane_ips contraildpdk)"
    nodes+=" $(get_ctlplane_ips contrailsriov)"
    check_tf_active $SSH_USER_OVERCLOUD "$nodes"
}

function collect_deployment_env() {
    if is_after_stage 'wait' ; then
        collect_overcloud_env
    fi
}
