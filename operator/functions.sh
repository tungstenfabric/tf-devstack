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

function openssl_enroll() {
    echo "INFO: enroll for external self-signed certs"
    local work_dir=${WORKSPACE}
    rm -rf $work_dir/ssl
    mkdir -p $work_dir/ssl
    CA_ROOT_CERT="${work_dir}/ssl/ca.crt" \
        CA_ROOT_KEY="${work_dir}/ssl/ca.key" \
        ${my_dir}/../contrib/create_ca_certs.sh
    cp ${work_dir}/ssl/ca.crt ${work_dir}/ssl/front-proxy-ca.crt
    cp ${work_dir}/ssl/ca.key ${work_dir}/ssl/front-proxy-ca.key
    mkdir -p ${work_dir}/ssl/etcd/
    cp ${work_dir}/ssl/ca.* ${work_dir}/ssl/etcd/

    local nodes="$CONTROLLER_NODES $AGENT_NODES"
    local tmp_ca_dir="/tmp/ca_certs_k8s"
    local k8s_ca_dir="/etc/kubernetes/ssl"
    local etcd_ca_dir="/etc/ssl/etcd/ssl"
    local machine
    for machine in $(echo $nodes | tr " " "\n" | sort -u) ; do
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

function ipa_enroll() {
    local nodes="$CONTROLLER_NODES $AGENT_NODES"
    local work_dir=${WORKSPACE}
    local machine
    for machine in $(echo "$nodes" | tr " " "\n" | sort -u) ; do
        local addr="$machine"
        scp $SSH_OPTIONS -rp "${work_dir}"/src/tungstenfabric/tf-devstack/contrib/ipa/enroll.sh "${machine}":/tmp
        echo "INFO: enroll node $machine to IPA"
        ssh $SSH_OPTIONS "$machine" /tmp/enroll.sh "$IPA_IP" "$IPA_ADMIN" "$IPA_PASSWORD" "$machine"
    done
}

function ipa_server_install() {
    local machine=$1
    local work_dir=${WORKSPACE}
    local addr="$machine"
    echo "INFO: copy freeipa_server_root.sh to node $machine"
    scp $SSH_OPTIONS -rp "${work_dir}"/src/tungstenfabric/tf-devstack/contrib/ipa/freeipa_setup_root.sh "${machine}":
    echo "INFO: install IPA server at $machine"

    if [ -n $NAMESERVER_LIST ]; then
        echo "INFO: Setup DNS servers $NAMESERVER_LIST"
        IPA_DNS1=$(echo $NAMESERVER_LIST | cut -d ',' -f1)
        IPA_DNS2=$(echo $NAMESERVER_LIST | cut -d ',' -f2)
    fi

    cat <<EOF | ssh $SSH_OPTIONS $machine
[[ "$DEBUG" == true ]] && set -x
export AdminPassword=$IPA_PASSWORD
export FreeIPAIP=$machine
export IPA_DNS1=$IPA_DNS1
export IPA_DNS2=$IPA_DNS2
sudo -E ./freeipa_setup_root.sh
EOF
    ssh $SSH_OPTIONS $machine cat /etc/ipa/ca.crt
}

#function get_ipa_crt() {
#    local machine=$1
#    ssh $SSH_OPTIONS $machine cat /etc/ipa/ca.crt
#}

function set_timeserver_node() {
    local ip_addr=$1
    local tf_devstack_path=$(dirname $my_dir)
    if [[ ! -n "$NTP_SERVERS" ]]; then
        echo "INFO: set_timeserver: Variable NTP_SERVERS is empty. Nothing to set"
        return
    fi
    echo "INFO: copying common/set_timeserver.sh and common/functions.sh to the $ip_addr"
    scp $SSH_OPTIONS -r $tf_devstack_path/common/set_timeserver.sh $tf_devstack_path/common/functions.sh $ip_addr:/tmp
    cat <<EOF | ssh $SSH_OPTIONS $ip_addr
[[ "$DEBUG" == true ]] && set -x
export NTP_SERVERS="$NTP_SERVERS"
echo "INFO: running set_timeserver.sh on the $ip_addr. See log at /tmp/set_timeserver.log"
/tmp/set_timeserver.sh
EOF
}

function rhel_setup_node() {
    local ip_addr=$1
    local tf_devstack_path=$(dirname $my_dir)
    scp $SSH_OPTIONS -r $tf_devstack_path $ip_addr:
    cat <<EOF | ssh $SSH_OPTIONS $ip_addr
[[ "$DEBUG" == true ]] && set -x
export DOMAIN=$DOMAIN
export NAMESERVER_LIST=$NAMESERVER_LIST
export NTP_SERVERS=$NTP_SERVERS
echo "INFO: running rhel_provisioning on the $ip_addr. See log at /tmp/rhel_provisioning.log"
./$(basename $tf_devstack_path)/common/rhel_provisioning.sh
EOF
}


function parallel_run() {
    local action=$1
    local jobs=""
    declare -A jobs_descr
    local ip_addr
    for ip_addr in ${CONTROLLER_NODES//,/ } ${AGENT_NODES//,/ } ${IPA_NODES//,/ } ; do
        $action $ip_addr &
        jobs_descr[$!]="$action $ip_addr"
        jobs+=" $!"
    done
    echo "INFO: Parallel $action. pids: $jobs. Waiting..."
    local res=0
    local i
    for i in $jobs ; do
        command wait $i || {
            echo "ERROR: failed ${jobs_descr[$i]}"
            res=1
        }
    done
    [[ "${res}" == 0 ]] || exit 1
}


