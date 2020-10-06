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
        local name
        openstack stack resource list --filter status=FAILED -n 10 -f json overcloud | jq -r -c ".[].resource_name" | while read name ; do
            echo "ERROR: $name" >> ./stack_failed_resources.log
            openstack stack resource show -f shell overcloud $name | sed 's/\\n/\n/g' >> ${log_dir}/stack_failed_resources.log
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
    if [[ -n "$overcloud_cont_prov_ip" ]]; then
        echo "$overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip"
        return
    fi
    [[ -z "$OS_AUTH_URL" ]] && source ~/stackrc
    openstack server list -c Networks -f value | awk -F '=' '{print $NF}' | xargs
}

function get_servers_ips_by_flavor() {
    local flavor=$1
    [[ -n "$overcloud_cont_prov_ip" && "$1" == 'control' ]] && echo $overcloud_cont_prov_ip && return
    [[ -n "$overcloud_ctrlcont_prov_ip" && "$1" == 'contrail-controller' ]] && echo $overcloud_ctrlcont_prov_ip && return
    [[ -n "$overcloud_compute_prov_ip" && "$1" == 'compute' ]] && echo $overcloud_compute_prov_ip && return

    [[ -z "$OS_AUTH_URL" ]] && source ~/stackrc
    openstack server list --flavor $flavor -c Networks -f value | awk -F '=' '{print $NF}' | xargs
}

function get_vip() {
    local vip_name=$1
    local openstack_node=$(get_servers_ips_by_flavor control | awk '{print $1}')
    ssh $ssh_opts $SSH_USER@$openstack_node sudo hiera -c /etc/puppet/hiera.yaml $vip_name
}

function get_openstack_node_ips() {
    local role=$1
    local subdomain=$2
    local openstack_node=$(get_servers_ips_by_flavor control | awk '{print $1}')
    ssh $ssh_opts $SSH_USER@$openstack_node \
         cat /etc/hosts | grep overcloud-${role}-[0-9]\.${subdomain} | awk '{print $1}'| xargs
}

function collect_overcloud_env() {
    if [[ "${DEPLOY_COMPACT_AIO,,}" == 'true' ]] ; then
        CONTROLLER_NODES=$(get_servers_ips_by_flavor control)
        AGENT_NODES="$CONTROLLER_NODES"
    elif [[ "${ENABLE_NETWORK_ISOLATION,,}" = true ]] ; then
        CONTROLLER_NODES="$(get_openstack_node_ips contrailcontroller internalapi)"
        AGENT_NODES="$(get_servers_ips_by_flavor compute) $(get_servers_ips_by_flavor compute-dpdk) $(get_servers_ips_by_flavor compute-sriov)"
        DEPLOYMENT_ENV['OPENSTACK_CONTROLLER_NODES']=$(get_openstack_node_ips controller internalapi)
    else
        CONTROLLER_NODES=$(get_servers_ips_by_flavor contrail-controller)
        AGENT_NODES=$(get_servers_ips_by_flavor compute)
    fi
    if [[ -f ~/overcloudrc ]] ; then
        source ~/overcloudrc
        DEPLOYMENT_ENV['AUTH_URL']=$(echo ${OS_AUTH_URL} | sed "s/overcloud/overcloud.internalapi/")
        DEPLOYMENT_ENV['AUTH_PASSWORD']="${OS_PASSWORD}"
        DEPLOYMENT_ENV['AUTH_REGION']="${OS_REGION_NAME}"
        DEPLOYMENT_ENV['AUTH_PORT']="35357"
    fi
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
        scp $ssh_opts $my_dir/../common/collect_logs.sh $SSH_USER@$ip:
        cat <<EOF | ssh $ssh_opts $SSH_USER@$ip
            export TF_LOG_DIR="/home/$SSH_USER/logs"
            cd /home/$SSH_USER
            ./collect_logs.sh create_log_dir
            ./collect_logs.sh collect_docker_logs
            ./collect_logs.sh collect_system_stats
            ./collect_logs.sh collect_contrail_logs
EOF
        source_name=$(ssh $ssh_opts $SSH_USER@$ip hostname -s)
        mkdir ${TF_LOG_DIR}/${source_name}
        scp -r $ssh_opts $SSH_USER@$ip:logs/* ${TF_LOG_DIR}/${source_name}/
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
sudo tee /etc/sysconfig/network-scripts/ifcfg-${vlan_id} > /dev/null <<EOF
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
    ifdown ${vlan_id}
    ifup ${vlan_id}
}

function wait_ssh() {
  local addr=$1
  local ssh_key=${2:-''}
  local max_iter=${3:-20}
  local iter=0
  local ssh_opts='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no'
  if [[ -n "$ssh_key" ]] ; then
    ssh_opts+=" -i $ssh_key"
  fi
  local tf=$(mktemp)
  while ! scp $ssh_opts -B $tf ${SSH_USER}@${addr}:/tmp/ ; do
    if (( iter >= max_iter )) ; then
      echo "Could not connect to VM $addr"
      exit 1
    fi
    echo "Waiting for VM $addr..."
    sleep 30
    ((++iter))
  done
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
export USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES
export OPENSTACK_VERSION="$OPENSTACK_VERSION"
export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION
export ENABLE_NETWORK_ISOLATION=$ENABLE_NETWORK_ISOLATION
export DEPLOY_COMPACT_AIO=$DEPLOY_COMPACT_AIO
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG"
export CONTRAIL_DEPLOYER_CONTAINER_TAG="$CONTRAIL_DEPLOYER_CONTAINER_TAG"
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export DEPLOYER_CONTAINER_REGISTRY="$DEPLOYER_CONTAINER_REGISTRY"
export OPENSTACK_CONTAINER_REGISTRY="$OPENSTACK_CONTAINER_REGISTRY"
export IPMI_PASSWORD="$IPMI_PASSWORD"
export ENABLE_TLS=$ENABLE_TLS

EOF

    #Removing duplicate lines
    awk '!a[$0]++' $env_file > $target_env_file
}
