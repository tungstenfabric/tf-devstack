
source $my_dir/providers/common/stages.sh

function provisioning() {
    if [[ "${USE_PREDEPLOYED_NODES,,}" != true ]]; then
        echo "ERROR: unsupported configuration for vexx: USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES"
        exit -1
    fi
    cd $WORKSPACE
    prepare_rhosp_env_file $WORKSPACE/rhosp-environment.sh
    $my_dir/providers/vexx/create_env.sh
    wait_ssh ${instance_ip} ${ssh_private_key}
    scp -r $ssh_opts rhosp-environment.sh $(dirname $my_dir) stack@${instance_ip}:
    if [[ -n "$ENABLE_TLS" ]] ; then
        wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
        scp -r $ssh_opts rhosp-environment.sh $(dirname $my_dir) stack@${instance_ip}:
    fi
}
