#Stages for VEXX deployment (it's part of run.sh)

export CONFIGURE_DOCKER_LIVERESTORE='false'

ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no"

function provisioning() {
    if [[ "${USE_PREDEPLOYED_NODES,,}" != true ]]; then
        echo "ERROR: unsupported configuration for vexx: USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES"
        exit 1
    fi
    cd $my_dir/providers/vexx
    ./create_env.sh
    wait_ssh ${mgmt_ip} ${ssh_private_key}
    if [[ -n "$ENABLE_TLS" ]] ; then
        wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
    fi
}

function machines() {
    cd $my_dir
    sudo -E $my_dir/undercloud/00_provision.sh
}

function undercloud() {
    cd $my_dir
    sudo ./undercloud/01_deploy_as_root.sh
    ./undercloud/02_deploy_as_stack.sh
    ./undercloud/${RHOSP_VERSION}_configure_registries_undercloud.sh
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
    echo \!\!\! tf: $(set -o | grep errexit)
    cd $my_dir
    ./overcloud/04_prepare_heat_templates.sh || exit 1
    ./overcloud/05_prepare_containers.sh     || exit 1
    ./overcloud/06_deploy_overcloud.sh       || exit 1
}

function logs() {
    collect_deployment_log
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    return 0
}

function collect_deployment_env() {
    collect_overcloud_env
}
