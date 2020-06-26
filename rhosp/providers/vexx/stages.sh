#Stages for VEXX deployment (it's part of run.sh)

export CONFIGURE_DOCKER_LIVERESTORE='false'

ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no"

function machines() {
    cd $my_dir
    sudo -E bash -c "source /home/$user/rhosp-environment.sh; $my_dir/undercloud/00_provision.sh"
}

function undercloud() {
    cd $my_dir
    sudo ./undercloud/01_deploy_as_root.sh
    ./undercloud/02_deploy_as_stack.sh
    ${RHOSP_VERSION}_configure_registries_undercloud.sh
}

#Overcloud nodes provisioning
function overcloud() {
    cd $my_dir
    if [[ "$RHOSP_VERSION" == 'rhosp13' ]] ; then
        ./overcloud/03_setup_predeployed_nodes_access.sh
    fi
    local jobs=""
    local res=0
    for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
        scp $ssh_opts ~/rhosp-environment.sh  ../common/collect_logs.sh \
            ../common/create_docker_config.sh ../common/jinja2_render.py \
            providers/common/* overcloud/03_setup_predeployed_nodes.sh \
            overcloud/${RHOSP_VERSION}_configure_registries_overcloud.sh $SSH_USER@$ip:
        ssh $ssh_opts $SSH_USER@$ip mkdir -p ./files
        scp $ssh_opts ../common/files/docker_daemon.json.j2 $SSH_USER@$ip:files/
        ssh $ssh_opts $SSH_USER@$ip sudo ./03_setup_predeployed_nodes.sh &
        jobs+=" $!"
    done
    echo Parallel pre-installation overcloud nodes. pids: $jobs. Waiting...
    local i
    for i in $jobs ; do
        command wait $i || res=1
    done
    if [[ "${res}" == 1 ]]; then
        echo errors appeared during overcloud nodes pre-installation. Exiting
        exit 1
    fi
}

#Overcloud stage
function tf() {
    cd $my_dir
    ./overcloud/04_prepare_heat_templates.sh
    ./overcloud/05_prepare_containers.sh
    ./overcloud/06_deploy_overcloud.sh
}


function _collect_stack_details() {
    local log_dir=$1
    [ -n "$log_dir" ] || {
        echo "WARNING: empty log_dir provided.. logs collection skipped"
        return
    }
    source ~/stackrc
    # collect stack details
    echo "INFO: collect stack ouputs"
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

function logs() {
    local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
    set +e

    #Collecting undercloud logs
    create_log_dir
    local host_name=$(hostname -s)
    mkdir ${TF_LOG_DIR}/${host_name}
    collect_system_stats $host_name
    _collect_stack_details ${TF_LOG_DIR}/${host_name}

    #Collecting overcloud logs
    for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/${SSH_USER}/logs" ./collect_logs.sh create_log_dir
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/${SSH_USER}/logs" ./collect_logs.sh collect_docker_logs
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/${SSH_USER}/logs" ./collect_logs.sh collect_system_stats
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/${SSH_USER}/logs" ./collect_logs.sh collect_contrail_logs
        host_name=$(ssh $ssh_opts $SSH_USER@$ip hostname -s)
        mkdir ${TF_LOG_DIR}/${host_name}
        scp -r $ssh_opts $SSH_USER@$ip:logs/* ${TF_LOG_DIR}/${host_name}/
    done

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs

    # Restore errexit state
    if [[ $errexit_state == 1 ]]; then
        set -e
    fi
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    return 0
}

function collect_deployment_env() {
    if $DEPLOY_COMPACT_AIO ; then
        CONTROLLER_NODES="${overcloud_cont_prov_ip}"
        AGENT_NODES="${overcloud_cont_prov_ip}"
    else
        CONTROLLER_NODES="${overcloud_ctrlcont_prov_ip}"
        AGENT_NODES="${overcloud_compute_prov_ip}"
    fi
    if [[ -f ~/overcloudrc ]]; then
        source ~/overcloudrc
        local internal_vip=$(ssh $ssh_opts $SSH_USER@$overcloud_cont_prov_ip sudo hiera -c /etc/puppet/hiera.yaml internal_api_virtual_ip)
        local os_auth_internal_api_url=$(echo ${OS_AUTH_URL} | sed "s/\(http[s]\{0,1\}:\/\/\).*\([:]{0,1}\/.*\)/\1${internal_vip}\2/g")
        DEPLOYMENT_ENV['AUTH_URL']="${os_auth_internal_api_url}"
        DEPLOYMENT_ENV['AUTH_PASSWORD']="${OS_PASSWORD}"
        DEPLOYMENT_ENV['AUTH_REGION']="${OS_REGION_NAME}"
        DEPLOYMENT_ENV['AUTH_PORT']="35357"
    fi
}
