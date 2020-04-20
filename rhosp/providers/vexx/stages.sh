#Stages for VEXX deployment (it's part of run.sh)

export CONFIGURE_DOCKER_LIVERESTORE='false'

ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

function machines() {
    cd $my_dir
    sudo -E bash -c "source /home/$user/rhosp-environment.sh; $my_dir/undercloud/00_provision.sh"
}

function undercloud() {
    cd $my_dir
    sudo ./undercloud/01_deploy_as_root.sh || return 1
    ./undercloud/02_deploy_as_stack.sh || return 1
    # No needs to have container registry on undercloud.
    # For now overcloud nodes download them directly from $CONTAINER_REGISTRY
    sudo -E CONTAINER_REGISTRY="" CONFIGURE_DOCKER_LIVERESTORE=false $my_dir/../common/create_docker_config.sh || return 1
    local insecure_registries=$(cat /etc/sysconfig/docker | awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' | tr -d '"')
    if [ -n "$CONTAINER_REGISTRY" ] && is_registry_insecure $CONTAINER_REGISTRY ; then
       insecure_registries+=" --insecure-registry $CONTAINER_REGISTRY"
    fi
    sudo sed -i '/^INSECURE_REGISTRY/d' /etc/sysconfig/docker
    echo "INSECURE_REGISTRY=\"$insecure_registries\""  | sudo tee -a /etc/sysconfig/docker
    if ! sudo systemctl restart docker ; then
        systemctl status docker.service
        journalctl -xe
        return 1
    fi
}

#Overcloud nodes provisioning
function overcloud() {
    cd $my_dir
    ./overcloud/03_setup_predeployed_nodes_access.sh
    local jobs=""
    local res=0
    for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
        scp $ssh_opts ~/rhosp-environment.sh  ../common/collect_logs.sh \
            ../common/create_docker_config.sh ../common/jinja2_render.py \
            providers/common/* overcloud/03_setup_predeployed_nodes.sh $SSH_USER@$ip:
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

function logs() {
    local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
    set +e

    #Collecting undercloud logs
    create_log_dir
    collect_system_stats
    hostname=$(hostname -s)
    mkdir ${TF_LOG_DIR}/${hostname}
    mv ${TF_LOG_DIR}/* ${TF_LOG_DIR}/${hostname}/ || true

    #Collecting overcloud logs
    for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/${SSH_USER}/logs" ./collect_logs.sh create_log_dir
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/${SSH_USER}/logs" ./collect_logs.sh collect_docker_logs
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/${SSH_USER}/logs" ./collect_logs.sh collect_system_stats
        ssh $ssh_opts $SSH_USER@$ip TF_LOG_DIR="/home/${SSH_USER}/logs" ./collect_logs.sh collect_contrail_logs
        hostname=$(ssh $ssh_opts $SSH_USER@$ip hostname -s)
        mkdir ${TF_LOG_DIR}/${hostname}
        scp -r $ssh_opts $SSH_USER@$ip:logs/* ${TF_LOG_DIR}/${hostname}/
    done

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    #rm -rf $TF_LOG_DIR

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
        CONTROLLER_NODES="${overcloud_cont_ip}"
        AGENT_NODES="${overcloud_cont_ip}"
    else
        CONTROLLER_NODES="${overcloud_ctrlcont_prov_ip}"
        AGENT_NODES="${overcloud_compute_prov_ip}"
    fi
    if [[ -f ~/overcloudrc ]]; then
        source ~/overcloudrc
        DEPLOYMENT_ENV['AUTH_URL']="${OS_AUTH_URL}"
        DEPLOYMENT_ENV['AUTH_PASSWORD']="${OS_PASSWORD}"
        DEPLOYMENT_ENV['AUTH_REGION']="${OS_REGION_NAME}"
    fi
}

