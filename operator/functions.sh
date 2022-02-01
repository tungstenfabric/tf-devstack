#!/bin/bash

function collect_logs_from_machines() {
    cat <<EOF >/tmp/logs.sh
#!/bin/bash
tgz_name=\$1
export WORKSPACE=/tmp/operator-logs
export TF_LOG_DIR=/tmp/operator-logs/logs
export DEPLOYER=$DEPLOYER
export SSL_ENABLE=$SSL_ENABLE
cd /tmp/operator-logs
source ./collect_logs.sh
collect_system_stats
collect_tf_status
collect_docker_logs
collect_kubernetes_objects_info
collect_kubernetes_logs
collect_kubernetes_service_statuses
collect_tf_logs
sudo chmod -R a+r logs
pushd logs
tar -czf \$tgz_name *
popd
cp logs/\$tgz_name \$tgz_name
sudo rm -rf logs
EOF
    chmod a+x /tmp/logs.sh

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local machine
    for machine in $(echo "$CONTROLLER_NODES $AGENT_NODES" | tr " " "\n" | sort -u) ; do
        local tgz_name="logs-$machine.tgz"
        mkdir -p $TF_LOG_DIR/$machine
        ssh $ssh_opts $machine "mkdir -p /tmp/operator-logs"
        scp $ssh_opts $my_dir/../common/collect_logs.sh $machine:/tmp/operator-logs/collect_logs.sh
        scp $ssh_opts /tmp/logs.sh $machine:/tmp/operator-logs/logs.sh
        ssh $ssh_opts $machine /tmp/operator-logs/logs.sh $tgz_name
        scp $ssh_opts $machine:/tmp/operator-logs/$tgz_name $TF_LOG_DIR/$machine/
        pushd $TF_LOG_DIR/$machine/
        tar -xzf $tgz_name
        rm -rf $tgz_name
        popd
    done
}

function openssl_gen_keys() {
    local work_dir=${WORKSPACE}
    mkdir -p $work_dir/ssl
    CA_ROOT_CERT="${work_dir}/ssl/ca.crt" CA_ROOT_KEY="${work_dir}/ssl/ca.key" ${my_dir}/../contrib/create_ca_certs.sh
    cp ${work_dir}/ssl/ca.crt ${work_dir}/ssl/front-proxy-ca.crt
    cp ${work_dir}/ssl/ca.key ${work_dir}/ssl/front-proxy-ca.key
    mkdir -p ${work_dir}/ssl/etcd/
    cp ${work_dir}/ssl/ca.* ${work_dir}/ssl/etcd/
}

function transfer_ca() {
    local work_dir=${WORKSPACE}
    local controller_nodes=${CONTROLLER_NODES}
    local tmp_ca_dir="/tmp/ca_certs_k8s"
    local k8s_ca_dir="/etc/kubernetes/ssl"
    local etcd_ca_dir="/etc/ssl/etcd/ssl"
    local machine
    for machine in $(echo $controller_nodes | tr " " "\n" | sort -u) ; do
        local addr="$machine"
        echo "INFO: copy CA to node $addr"
        [ -z "$SSH_USER" ] || addr="$SSH_USER@$addr"
        scp $SSH_OPTIONS -rp ${work_dir}/ssl ${addr}:${tmp_ca_dir}
        cat << EOF | ssh $SSH_OPTIONS $addr
export DEBUG=$DEBUG
sudo mkdir -p ${k8s_ca_dir}
sudo cp -r ${tmp_ca_dir}/* ${k8s_ca_dir}/
sudo chmod -R a=wrX  ${k8s_ca_dir}
sudo mkdir -p ${etcd_ca_dir}
sudo cp ${tmp_ca_dir}/ca.key ${etcd_ca_dir}/ca-key.pem
sudo cp ${tmp_ca_dir}/ca.crt ${etcd_ca_dir}/ca.pem
sudo chmod -R a=wrX  ${etcd_ca_dir}
rm -rf ${tmp_ca_dir}
EOF
    done
}
