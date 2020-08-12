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
    if [[ "${DEPLOY_COMPACT_AIO,,}" == 'true' ]] ; then
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
        DEPLOYMENT_ENV['AUTH_URL']="${os_auth_internal_api_url}"
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
    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    set -e
}

function set_rhosp_version() {
    case "$OPENSTACK_VERSION" in
    "queens" )
        export RHEL_VERSION='rhel7'
        export RHOSP_VERSION='rhosp13'
        ;;
    "train" )
        export RHEL_VERSION='rhel8'
        export RHOSP_VERSION='rhosp16'
        ;;
    *)
        echo "Variable OPENSTACK_VERSION is unset or incorrect"
        exit 1
        ;;
esac
}
