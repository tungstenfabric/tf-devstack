#!/bin/bash

function is_registry_insecure() {
    echo "DEBUG: is_registry_insecure: $@"
    local registry=`echo $1 | sed 's|^.*://||' | cut -d '/' -f 1`
    if  curl -s -I --connect-timeout 60 http://$registry/v2/ ; then
        echo "DEBUG: is_registry_insecure: $registry is insecure"
        return 0
    fi
    echo "DEBUG: is_registry_insecure: $registry is secure"
    return 1
}

function collect_stack_details() {
    local log_dir=$1
    [ -n "$log_dir" ] || {
        echo "WARNING: empty log_dir provided.. logs collection skipped"
        return
    }
    source ~/stackrc
    # collect stack details
    echo "INFO: collect stack outputs"
    openstack stack output show -f json --all overcloud | sed 's/\\n/\n/g' > ${log_dir}/stack_outputs.log
    echo "INFO: collect stack environment"
    openstack stack environment show -f json overcloud | sed 's/\\n/\n/g' > ${log_dir}/stack_environment.log

    # ensure stack is not failed
    status=$(openstack stack show -f json overcloud | jq ".stack_status")
    if [[ ! "$status" =~ 'COMPLETE' ]] ; then
        echo "ERROR: stack status $status"
        echo "ERROR: openstack stack failures list"
        openstack stack failures list --long overcloud | sed 's/\\n/\n/g' | tee ${log_dir}/stack_failures.log

        echo "INFO: collect failed resources"
        rm -f ${log_dir}/stack_failed_resources.log
        local resource
        local stack
        openstack stack resource list --filter status=FAILED -n 10 -f json overcloud | jq -r -c ".[] | .resource_name+ \" \" + .stack_name" | while read resource stack ; do
            echo "ERROR: $resource $stack" >> ./stack_failed_resources.log
            openstack stack resource show -f shell $stack $resource | sed 's/\\n/\n/g' >> ${log_dir}/stack_failed_resources.log
            echo -e "\n\n" >> ./stack_failed_resources.log
        done

        echo "INFO: collect failed deployments"
        rm -f ${log_dir}/stack_failed_deployments.log
        local id
        openstack software deployment list --format json | jq -r -c ".[] | select(.status != \"COMPLETE\") | .id" | while read id ; do
            openstack software deployment show --format shell $id | sed 's/\\n/\n/g' >> ${log_dir}/stack_failed_deployments.log
            echo -e "\n\n" >> ./stack_failed_deployments.log
        done
    fi
}

function get_servers_ips() {
    if [[ "$USE_PREDEPLOYED_NODES" == true ]]; then
        echo "${overcloud_cont_prov_ip//,/ } ${overcloud_compute_prov_ip//,/ } ${overcloud_ctrlcont_prov_ip//,/ }"
        return
    fi
    [[ -z "$OS_AUTH_URL" ]] && source ~/stackrc
    openstack server list -c Networks -f value | awk -F '=' '{print $NF}' | xargs
}

function get_servers_ips_by_name() {
    local name=$1
    if [[ "$USE_PREDEPLOYED_NODES" == true ]]; then
        [[ "$name" == 'controller' ]] && echo "${overcloud_cont_prov_ip//,/ }" && return
        [[ "$name" == 'contrailcontroller' ]] && echo "${overcloud_ctrlcont_prov_ip//,/ }" && return
        [[ "$name" == 'novacompute' ]] && echo "${overcloud_compute_prov_ip//,/ }" && return
        echo "ERROR: unsupported node role $name"
        exit 1;
    fi
    [[ -z "$OS_AUTH_URL" ]] && source ~/stackrc
    openstack server list -c Networks -f value --name "\-${name}-" | awk -F '=' '{print $NF}' | xargs
}

function get_vip() {
    local vip_name=$1
    ssh $ssh_opts $SSH_USER_OVERCLOUD@$openstack_node sudo hiera -c /etc/puppet/hiera.yaml $vip_name
}

function update_undercloud_etc_hosts() {
    # patch hosts to resole overcloud by fqdn
    echo "INFO: remove from /etc/hosts old overcloud fqdns if any"
    sudo sed -i "/overcloud.${domain}/d" /etc/hosts
    sudo sed -i "/overcloud.internalapi.${domain}/d" /etc/hosts
    sudo sed -i "/overcloud.ctlplane.${domain}/d" /etc/hosts
    sudo sed -i "/overcloud-/d" /etc/hosts

    local openstack_node=$(get_servers_ips_by_name controller | awk '{print $1}')
    local public_vip=$(get_vip public_virtual_ip $openstack_node)
    local internal_api_vip=$(get_vip internal_api_virtual_ip $openstack_node)
    local ctlplane_vip=$fixed_vip
    echo "INFO: update /etc/hosts for overcloud vips fqdns"
    cat <<EOF | sudo tee -a /etc/hosts
# Overcloud VIPs and Nodes
${public_vip} overcloud.${domain}
${internal_api_vip} overcloud.internalapi.${domain}
${ctlplane_vip} overcloud.ctlplane.${domain}
EOF
    ssh $ssh_opts $SSH_USER_OVERCLOUD@$openstack_node sudo grep "overcloud\-" /etc/hosts 2>/dev/null | sudo tee -a /etc/hosts

    echo "INFO: updated undercloud /etc/hosts"
    sudo cat /etc/hosts
}

function get_openstack_node_ips() {
    local openstack_node=$1
    local name=$2
    local network=$3
    if [[ "${USE_PREDEPLOYED_NODES,,}" == true ]]; then
        [[ "$name" == 'controller' ]] && echo "${overcloud_cont_prov_ip//,/ }" && return
        [[ "$name" == 'contrailcontroller' ]] && echo "${overcloud_ctrlcont_prov_ip//,/ }" && return
        [[ "$name" == 'novacompute' ]] && echo "${overcloud_compute_prov_ip//,/ }" && return
        [[ "$name" == 'contraildpdk' ]] && echo "${overcloud_dpdk_prov_ip//,/ }" && return
        [[ "$name" == 'contrailsriov' ]] && echo "${overcloud_sriov_prov_ip//,/ }" && return
        [[ "$name" == 'storage' ]] && echo "${overcloud_ceph_prov_ip//,/ }" && return
        echo "ERROR: unsupported node role $name"
        exit 1;
    fi
    ssh $ssh_opts $SSH_USER_OVERCLOUD@$openstack_node \
         cat /etc/hosts | grep overcloud-${name}-[0-9]\.${network} | awk '{print $1}'| xargs
}

function _print_fqdn() {
    [ -z "$2" ] || printf "%s.$1 " ${2//,/ }
}

function get_openstack_node_names() {
    local openstack_node=$1
    local name=$2
    local network=$3
    if [[ "${USE_PREDEPLOYED_NODES,,}" == true ]]; then
        local suffix="$domain"
        if [[ "${ENABLE_NETWORK_ISOLATION,,}" == true ]]; then
            # use network param only for network isolation case
            suffix="${network}.${suffix}" 
        fi
        [[ "$name" == 'controller' ]] && _print_fqdn $suffix $overcloud_cont_instance && return
        [[ "$name" == 'contrailcontroller' ]] && _print_fqdn $suffix $overcloud_ctrlcont_instance && return
        [[ "$name" == 'novacompute' ]] && _print_fqdn $suffix $overcloud_compute_instance && return
        [[ "$name" == 'contraildpdk' ]] && _print_fqdn $suffix $overcloud_dpdk_instance && return
        [[ "$name" == 'contrailsriov' ]] && _print_fqdn $suffix $overcloud_sriov_instance && return
        [[ "$name" == 'storage' ]] && _print_fqdn $suffix $overcloud_ceph_instance && return
        echo "ERROR: unsupported node role $name"
        exit 1;
    fi
    ssh $ssh_opts $SSH_USER_OVERCLOUD@$openstack_node \
         cat /etc/hosts | grep overcloud-${name}-[0-9]\.${network} | awk '{print $2}'| xargs
}

function get_openstack_nodes() {
    if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
        get_openstack_node_names $@
    else
        get_openstack_node_ips $@
    fi
}

function collect_overcloud_env() {
    local openstack_node=$(get_servers_ips_by_name controller | awk '{print $1}')
    DEPLOYMENT_ENV['OPENSTACK_CONTROLLER_NODES']=$(get_openstack_nodes $openstack_node controller internalapi)
    CONTROLLER_NODES="$(get_openstack_nodes $openstack_node contrailcontroller internalapi)"
    if [ -z "$CONTROLLER_NODES" ] ; then
        # Openstack and Contrail Controllers are on same nodes (aio)
        CONTROLLER_NODES="${DEPLOYMENT_ENV['OPENSTACK_CONTROLLER_NODES']}"
    fi
    AGENT_NODES="$(get_openstack_nodes $openstack_node novacompute tenant)"
    if [ -z "$AGENT_NODES" ] ; then
        # Agents and Contrail Controllers are on same nodes (aio)
        AGENT_NODES="$CONTROLLER_NODES"
    fi
    DEPLOYMENT_ENV['CONTROL_NODES']="$(get_openstack_nodes $openstack_node contrailcontroller tenant)"
    DEPLOYMENT_ENV['DPDK_AGENT_NODES']=$(get_openstack_nodes $openstack_node contraildpdk tenant)
    DEPLOYMENT_ENV['SRIOV_AGENT_NODES']=$(get_openstack_nodes $openstack_node contrailsriov tenant)
    [ -z "${DEPLOYMENT_ENV['DPDK_AGENT_NODES']}" ] || AGENT_NODES+=" ${DEPLOYMENT_ENV['DPDK_AGENT_NODES']}"
    [ -z "${DEPLOYMENT_ENV['SRIOV_AGENT_NODES']}" ] || AGENT_NODES+=" ${DEPLOYMENT_ENV['SRIOV_AGENT_NODES']}"
    if [[ -f ~/overcloudrc ]] ; then
        source ~/overcloudrc
        DEPLOYMENT_ENV['AUTH_URL']=$(echo ${OS_AUTH_URL} | sed "s/overcloud/overcloud.internalapi/")
        DEPLOYMENT_ENV['AUTH_PASSWORD']="${OS_PASSWORD}"
        DEPLOYMENT_ENV['AUTH_REGION']="${OS_REGION_NAME}"
        DEPLOYMENT_ENV['AUTH_PORT']="35357"
    fi
    DEPLOYMENT_ENV['SSH_USER']="$SSH_USER_OVERCLOUD"
    if [ -n "$ENABLE_TLS" ] ; then
        DEPLOYMENT_ENV['SSL_ENABLE']='true'
        if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
            local cafile='/etc/ipa/ca.crt'
        else
            local cafile='/etc/contrail/ssl/certs/ca-cert.pem'
        fi
        DEPLOYMENT_ENV['SSL_KEY']="$(ssh $ssh_opts $SSH_USER_OVERCLOUD@$openstack_node sudo base64 -w 0 /etc/contrail/ssl/private/server-privkey.pem 2>/dev/null)"
        DEPLOYMENT_ENV['SSL_CERT']="$(ssh $ssh_opts $SSH_USER_OVERCLOUD@$openstack_node sudo base64 -w 0 /etc/contrail/ssl/certs/server.pem 2>/dev/null)"
        DEPLOYMENT_ENV['SSL_CACERT']="$(ssh $ssh_opts $SSH_USER_OVERCLOUD@$openstack_node sudo base64 -w 0 $cafile 2>/dev/null)"
    fi
    DEPLOYMENT_ENV['HUGE_PAGES_1G']=$vrouter_huge_pages_1g
}

function collect_deployment_log() {
    #Collecting undercloud logs
    local host_name=$(hostname -s)
    create_log_dir
    mkdir ${TF_LOG_DIR}/${host_name}
    collect_system_stats $host_name
    collect_stack_details ${TF_LOG_DIR}/${host_name}
    if [[ -e /var/lib/mistral/overcloud/ansible.log ]] ; then
        cp /var/lib/mistral/overcloud/ansible.log ${TF_LOG_DIR}/${host_name}/
    fi

    #Collecting overcloud logs
    local ip=''
    for ip in $(get_servers_ips); do
        scp $ssh_opts $my_dir/../common/collect_logs.sh $SSH_USER_OVERCLOUD@$ip:
        cat <<EOF | ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip
            export TF_LOG_DIR="/home/$SSH_USER_OVERCLOUD/logs"
            cd /home/$SSH_USER_OVERCLOUD
            ./collect_logs.sh create_log_dir
            ./collect_logs.sh collect_docker_logs
            ./collect_logs.sh collect_system_stats
            ./collect_logs.sh collect_contrail_logs
EOF
        source_name=$(ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip hostname -s)
        mkdir ${TF_LOG_DIR}/${source_name}
        scp -r $ssh_opts $SSH_USER_OVERCLOUD@$ip:logs/* ${TF_LOG_DIR}/${source_name}/
    done

    # Save to archive all yaml files and tripleo templates
    tar -czf ${TF_LOG_DIR}/tht.tgz -C ~ *.yaml tripleo-heat-templates

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs

    set -e
}

function add_vlan_interface() {
    local vlan_id=$1
    local phys_dev=$2
    local ip_addr=$3
    local net_mask=$4
cat <<EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-${vlan_id}
# This file is autogenerated by tf-devstack
ONBOOT=yes
BOOTPROTO=static
HOTPLUG=no
NM_CONTROLLED=no
PEERDNS=no
USERCTL=yes
VLAN=yes
DEVICE=$vlan_id
PHYSDEV=$phys_dev
IPADDR=$ip_addr
NETMASK=$net_mask
EOF
    echo "INFO: ifup for /etc/sysconfig/network-scripts/ifcfg-${vlan_id}"
    sudo cat /etc/sysconfig/network-scripts/ifcfg-${vlan_id}
    sudo ifdown ${vlan_id} || true
    sudo ifup ${vlan_id}
}

function wait_ssh() {
    local addr=$1
    local ssh_key=${2:-''}
    if [[ -n "$ssh_key" ]] ; then
        ssh_key=" -i $ssh_key"
    fi
    local interval=5
    local max=100
    local silent_cmd=1
    [[ "$DEBUG" != true ]] || silent_cmd=0 
    if ! wait_cmd_success "ssh $ssh_opts $ssh_key ${SSH_USER}@${addr} uname -n" $interval $max $silent_cmd ; then
      echo "ERROR: Could not connect to VM $addr"
      exit 1
    fi
    echo "INFO: VM $addr is available"
}

function expand() {
    while read -r line; do
        if [[ "$line" =~ ^export ]]; then
            line="${line//\\/\\\\}"
            line="${line//\"/\\\"}"
            line="${line//\`/\\\`}"
            eval echo "\"$line\""
        else
            echo $line
        fi
    done
}

function prepare_rhosp_env_file() {
    local target_env_file=$1
    local env_file=$(mktemp)
    source $my_dir/../../config/common.sh
    cat $my_dir/../../config/common.sh | expand >> $env_file || true
    source $my_dir/../../config/${RHEL_VERSION}_env.sh
    cat $my_dir/../../config/${RHEL_VERSION}_env.sh | grep '^export' | expand >> $env_file || true
    source $my_dir/../../config/${PROVIDER}_env.sh
    cat $my_dir/../../config/${PROVIDER}_env.sh | grep '^export' | expand >> $env_file || true
    cat <<EOF >> $env_file

export DEBUG=$DEBUG
export PROVIDER=$PROVIDER
export OPENSTACK_VERSION="$OPENSTACK_VERSION"
export USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES
export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION
export ENABLE_NETWORK_ISOLATION=$ENABLE_NETWORK_ISOLATION
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG"
export CONTRAIL_DEPLOYER_CONTAINER_TAG="$CONTRAIL_DEPLOYER_CONTAINER_TAG"
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export DEPLOYER_CONTAINER_REGISTRY="$DEPLOYER_CONTAINER_REGISTRY"
export OPENSTACK_CONTAINER_REGISTRY="$OPENSTACK_CONTAINER_REGISTRY"
export ENABLE_TLS=$ENABLE_TLS

EOF

    #Removing duplicate lines
    awk '!a[$0]++' $env_file > $target_env_file
}
