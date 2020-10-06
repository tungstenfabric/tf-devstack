
source $my_dir/providers/common/stages.sh

# TODO: to be moved out devstack at later steps
function provisioning() {
    cd $WORKSPACE
    prepare_rhosp_env_file $WORKSPACE/rhosp-environment.sh
    scp -r $ssh_opts rhosp-environment.sh $(dirname $my_dir) stack@${instance_ip}:
    wait_ssh ${instance_ip} ${ssh_private_key}
    scp -r $ssh_opts rhosp-environment.sh $(dirname $my_dir) stack@${instance_ip}:
    if [[ -n "$ENABLE_TLS" ]] ; then
        wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
        scp -r $ssh_opts rhosp-environment.sh $(dirname $my_dir) root@${ipa_mgmt_ip}:
    fi
}
