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

function patch_docker_configs(){
    # No needs to have container registry on undercloud.
    # For now overcloud nodes download them directly from $CONTAINER_REGISTRY
    sudo -E CONTAINER_REGISTRY="" CONFIGURE_DOCKER_LIVERESTORE=false $my_dir/../common/create_docker_config.sh || return 1
    local insecure_registries=$(sudo awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' /etc/sysconfig/docker | tr -d '"')
    if [ -n "$CONTAINER_REGISTRY" ] && is_registry_insecure $CONTAINER_REGISTRY ; then
       insecure_registries+=" --insecure-registry $CONTAINER_REGISTRY"
    fi
    sudo sed -i '/^INSECURE_REGISTRY/d' /etc/sysconfig/docker
    echo "INSECURE_REGISTRY=\"$insecure_registries\""  | sudo tee -a /etc/sysconfig/docker
    if ! sudo systemctl restart docker ; then
        sudo systemctl status docker.service
        sudo journalctl -xe
        return 1
    fi
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
            openstack stack resource show -f value overcloud $name | sed 's/\\n/\n/g' >> ${log_dir}/stack_failed_resources.log
        done

        echo "INFO: collect failed deployments"
        rm -f ${log_dir}/stack_failed_deployments.log
        local id
        openstack software deployment list --format json | jq ".[] | select(.status != \"COMPLETE\") | .id" | while read id ; do
            openstack software deployment show --format value $id | sed 's/\\n/\n/g' >> ${log_dir}/stack_failed_deployments.log
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

function collect_overcloud_env() {
    if [[ "$DEPLOY_COMPACT_AIO" == "true" ]] ; then
        CONTROLLER_NODES=$(get_servers_ips_by_flavor control)
        AGENT_NODES="$CONTROLLER_NODES"
    else
        CONTROLLER_NODES=$(get_servers_ips_by_flavor contrail-controller)
        AGENT_NODES=$(get_servers_ips_by_flavor compute)
    fi
    if [[ -f ~/overcloudrc ]]; then
        source ~/overcloudrc
        local CONTROLLER_NODE=$(echo ${CONTROLLER_NODES} | awk '{print $1}')
        internal_vip=$(ssh $ssh_opts $SSH_USER@$CONTROLLER_NODE sudo hiera -c /etc/puppet/hiera.yaml internal_api_virtual_ip)
        os_auth_internal_api_url=$(echo $OS_AUTH_URL | sed "s#[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+#$internal_vip#")
    fi
}

function collect_deployment_log() {
    #Collecting undercloud logs
    local host_name=$(hostname -s)
    create_log_dir
    mkdir ${TF_LOG_DIR}/${host_name}
    collect_system_stats $host_name
    collect_stack_details ${TF_LOG_DIR}/${host_name}

    #Collecting overcloud logs
    local ip=''
    for ip in $(get_servers_ips); do
        scp $ssh_opts $my_dir/../common/collect_logs.sh $SSH_USER@$ip:
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/$SSH_USER/logs" ./collect_logs.sh create_log_dir
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/$SSH_USER/logs" ./collect_logs.sh collect_docker_logs
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/$SSH_USER/logs" ./collect_logs.sh collect_system_stats
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/$SSH_USER/logs" ./collect_logs.sh collect_contrail_logs
        source_name=$(ssh $ssh_opts $SSH_USER@$ip hostname -s)
        mkdir ${TF_LOG_DIR}/${host_name}
        scp -r $ssh_opts $SSH_USER@$ip:logs/* ${TF_LOG_DIR}/${source_name}/
    done
    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    set -e
}

function add_overcloud_user() {
    local pub_key=$(cat ~/.ssh/id_rsa.pub)
    local ip=''
    for ip in $(get_servers_ips); do
        ssh $ssh_opts heat-admin@$ip "id -u $SSH_USER" && continue
        cat <<EOF | ssh $ssh_opts -t heat-admin@$ip
sudo useradd $SSH_USER
echo "$SSH_USER ALL=(root) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/$SSH_USER
sudo chmod 440 /etc/sudoers.d/$SSH_USER
sudo mkdir /home/$SSH_USER/.ssh
echo "$pub_key" | sudo tee -a /home/$SSH_USER/.ssh/authorized_keys
sudo chmod 700 /home/$SSH_USER/.ssh
sudo chmod 600 /home/$SSH_USER/.ssh/authorized_keys
sudo chown -R $SSH_USER:$SSH_USER /home/$SSH_USER/
EOF
    done
}
