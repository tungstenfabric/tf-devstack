
function _predeploy_undercloud() {
    # ssh config to do not check host keys and avoid garbadge in known hosts files
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cat <<EOF >~/.ssh/config
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
    if [[ -n "$EXTERNAL_CONTROLLER_NODES" && -n "$EXTERNAL_CONTROLLER_SSH_USER" ]] ; then
        local i
        for i in ${EXTERNAL_CONTROLLER_NODES//,/ } ; do
        cat <<EOF >>~/.ssh/config
Host $i
    User $EXTERNAL_CONTROLLER_SSH_USER
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
        done
    fi

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

    ensure_fqdn ${domain}
}

function _setup_ipa() {
    local fqdn=$(hostname -f)
    echo "INFO: Setup IPA server ${ipa_mgmt_ip}"
    if [ -n $NAMESERVER_LIST ]; then
        echo "INFO: Setup DNS servers $NAMESERVER_LIST"
        IPA_DNS1=$(echo $NAMESERVER_LIST | cut -d ',' -f1)
        IPA_DNS2=$(echo $NAMESERVER_LIST | cut -d ',' -f2)
    fi
    cat <<EOF | ssh $ssh_opts $SSH_USER@${ipa_mgmt_ip}
source rhosp-environment.sh
[[ "$DEBUG" == true ]] && set -x
./tf-devstack/common/rhel_provisioning.sh
export UndercloudFQDN=$fqdn
export AdminPassword=$ADMIN_PASSWORD
export IPA_DNS1=$IPA_DNS1
export IPA_DNS2=$IPA_DNS2
export FreeIPAIP=$ipa_prov_ip
export FreeIPAIPSubnet=$prov_subnet_len
export IPA_IFACE=$(ip -o link | grep ether | awk '{print($2)}' | tr -d ':.*' | head -n 2 | tail -n1)
[ -n "$IPA_IFACE" ] || IPA_IFACE="eth1"
./tf-devstack/rhosp/ipa/freeipa_setup.sh
EOF
}

function _overcloud_setup_overcloud_node() {
    local ip_addr=$1
    local tf_devstack_path=$(dirname $my_dir)
    echo "INFO: predeploying node $ip_addr"
    scp $ssh_opts -r rhosp-environment.sh $tf_devstack_path $SSH_USER_OVERCLOUD@$ip_addr:
    ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip_addr ./$(basename $tf_devstack_path)/rhosp/overcloud/03_setup_predeployed_nodes.sh
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
    $my_dir/../common/rhel_provisioning.sh &
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

function tf_flavors() {
    cd
    if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
        $my_dir/overcloud/02_manage_overcloud_flavors.sh
    fi
}

function tf_templates() {
    cd
    $my_dir/overcloud/04_prepare_heat_templates.sh
}

function tf_containers() {
    cd
    $my_dir/overcloud/05_prepare_containers.sh
}

# TODO:
#   - move flavor into overcloud stage
#   - split containers preparation into openstack and contrail parts
#     and move openstack part into overcloud stage
#Overcloud stage w/o deploy for debug and customizations pruposes
function tf_no_deploy() {
    tf_flavors
    tf_templates
    tf_containers
}

function tf_deploy() {
    cd
    $my_dir/overcloud/06_deploy_overcloud.sh
}

function tf_post_deploy() {
    cd
    $my_dir/overcloud/07_post_deploy_overcloud.sh
}

function tf() {
    tf_no_deploy
    tf_deploy
    tf_post_deploy
}

function logs() {
    collect_deployment_log
}

function is_active() {
    # Services to check in wait stage
    CONTROLLER_SERVICES['_']=""
    CONTROLLER_SERVICES['kubernetes']=""
    CONTROLLER_SERVICES['analytics']+="redis "

    local agent_nodes=""
    local controller_nodes=""
    if [ -z "$EXTERNAL_CONTROLLER_NODES" ] ; then
        controller_nodes="$(get_ctlplane_ips contrailcontroller)"
        if [ -z "$controller_nodes" ] ; then
            # AIO
            controller_nodes="$(get_ctlplane_ips controller)"
            agent_nodes=$controller_nodes
        fi
    fi
    agent_nodes+=" $(get_ctlplane_ips novacompute)"
    agent_nodes+=" $(get_ctlplane_ips contraildpdk)"
    agent_nodes+=" $(get_ctlplane_ips contrailsriov)"
    check_tf_active $SSH_USER_OVERCLOUD "$controller_nodes $agent_nodes"
    check_tf_services $SSH_USER_OVERCLOUD "$controller_nodes" "$agent_nodes"
}

function collect_deployment_env() {
    if is_after_stage 'wait' ; then
        collect_overcloud_env
    fi
}
