#!/bin/bash

function collect_deployment_log() {
    set +e
    #Collecting undercloud logs
    local host_name=$(hostname -s)
    create_log_dir
    mkdir ${TF_LOG_DIR}/${host_name}
    collect_system_stats $host_name
    collect_openstack_logs $host_name
    pushd  ${TF_LOG_DIR}/${host_name}
    collect_docker_logs $CONTAINER_CLI_TOOL
    popd
    collect_stack_details ${TF_LOG_DIR}/${host_name}
    if [[ -e /var/lib/mistral/overcloud/ansible.log ]] ; then
        sudo cp /var/lib/mistral/overcloud/ansible.log ${TF_LOG_DIR}/${host_name}/
    fi

    #Collecting overcloud logs
    local ip=''
    for ip in $(get_ctlplane_ips); do
        scp $ssh_opts $my_dir/../common/collect_logs.sh $SSH_USER_OVERCLOUD@$ip:
        if [[ $EXTERNAL_CONTROLLER_NODES =~ $ip ]] ; then
            cat <<EOF | ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip
[[ "$DEBUG" == true ]] && set -x
set +e
export TF_LOG_DIR="/home/$SSH_USER_OVERCLOUD/logs"
cd /home/$SSH_USER_OVERCLOUD
./collect_logs.sh create_log_dir
./collect_logs.sh collect_docker_logs
./collect_logs.sh collect_kubernetes_objects_info
./collect_logs.sh collect_kubernetes_logs
./collect_logs.sh collect_kubernetes_service_statuses
./collect_logs.sh collect_system_stats
./collect_logs.sh collect_openstack_logs
./collect_logs.sh collect_tf_status
./collect_logs.sh collect_tf_logs
./collect_logs.sh collect_core_dumps

[[ ! -f /var/log/ipaclient-install.log ]] || {
    sudo cp /var/log/ipaclient-install.log \$TF_LOG_DIR
    sudo chown $SSH_USER_OVERCLOUD:$SSH_USER_OVERCLOUD \$TF_LOG_DIR/ipaclient-install.log
    sudo chmod 644 \$TF_LOG_DIR/ipaclient-install.log
}
EOF
        else
            cat <<EOF | ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip
[[ "$DEBUG" == true ]] && set -x
set +e
export TF_LOG_DIR="/home/$SSH_USER_OVERCLOUD/logs"
cd /home/$SSH_USER_OVERCLOUD
./collect_logs.sh create_log_dir
./collect_logs.sh collect_docker_logs $CONTAINER_CLI_TOOL
./collect_logs.sh collect_system_stats
./collect_logs.sh collect_openstack_logs
./collect_logs.sh collect_tf_status
./collect_logs.sh collect_tf_logs
./collect_logs.sh collect_core_dumps

[[ ! -f /var/log/ipaclient-install.log ]] || {
    sudo cp /var/log/ipaclient-install.log \$TF_LOG_DIR
    sudo chown $SSH_USER_OVERCLOUD:$SSH_USER_OVERCLOUD \$TF_LOG_DIR/ipaclient-install.log
    sudo chmod 644 \$TF_LOG_DIR/ipaclient-install.log
}
EOF
        fi
        local source_name=$(ssh $ssh_opts $SSH_USER_OVERCLOUD@$ip hostname -s)
        mkdir ${TF_LOG_DIR}/${source_name}
        rsync -a --safe-links -e "ssh $ssh_opts" $SSH_USER_OVERCLOUD@$ip:logs/ ${TF_LOG_DIR}/${source_name}/
    done
    if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
        scp $ssh_opts $my_dir/../common/collect_logs.sh $SSH_USER@$ipa_mgmt_ip:
        cat <<EOF | ssh $ssh_opts $SSH_USER@${ipa_mgmt_ip}
[[ "$DEBUG" == true ]] && set -x
set +e
export TF_LOG_DIR="/home/$SSH_USER/logs"
cd /home/$SSH_USER
./collect_logs.sh create_log_dir
./collect_logs.sh collect_system_stats
./collect_logs.sh collect_core_dumps
[[ ! -f /var/log/ipaclient-install.log ]] || {
    sudo cp /var/log/ipaclient-install.log \$TF_LOG_DIR
    sudo chown $SSH_USER:$SSH_USER \$TF_LOG_DIR/ipaclient-install.log
    sudo chmod 644 \$TF_LOG_DIR/ipaclient-install.log
}
[[ ! -f /var/log/ipaserver-install.log ]] || {
    sudo cp /var/log/ipaserver-install.log \$TF_LOG_DIR
    sudo chown $SSH_USER:$SSH_USER \$TF_LOG_DIR/ipaserver-install.log
    sudo chmod 644 \$TF_LOG_DIR/ipaserver-install.log
}
EOF
        mkdir ${TF_LOG_DIR}/ipa
        rsync -a --safe-links -e "ssh $ssh_opts" $SSH_USER@$ip:logs/ ${TF_LOG_DIR}/ipa/
    fi

    # Save to archive all yaml files and tripleo templates
    tar -czf ${TF_LOG_DIR}/tht.tgz -C ~ *.yaml tripleo-heat-templates
    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
}

