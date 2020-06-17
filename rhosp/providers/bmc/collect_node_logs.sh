#!/bin/bash -e

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
source "$my_dir/../../../common/common.sh"
source "$my_dir/../../../common/collect_logs.sh"
source "$my_dir/../common/functions.sh"

set +e
#Collecting undercloud logs
create_log_dir
host_name=$(hostname -s)
mkdir ${TF_LOG_DIR}/${host_name}
collect_system_stats $host_name
collect_stack_details ${TF_LOG_DIR}/${host_name}

#Collecting overcloud logs
for ip in $(get_servers_ips); do
    scp $ssh_opts $my_dir/../../../common/collect_logs.sh heat-admin@$ip:
    ssh $ssh_opts heat-admin@$ip TF_LOG_DIR="/home/heat-admin/logs" ./collect_logs.sh create_log_dir
    ssh $ssh_opts heat-admin@$ip TF_LOG_DIR="/home/heat-admin/logs" ./collect_logs.sh collect_docker_logs
    ssh $ssh_opts heat-admin@$ip TF_LOG_DIR="/home/heat-admin/logs" ./collect_logs.sh collect_system_stats
    ssh $ssh_opts heat-admin@$ip TF_LOG_DIR="/home/heat-admin/logs" ./collect_logs.sh collect_contrail_logs
    host_name=$(ssh $ssh_opts heat-admin@$ip hostname -s)
    mkdir ${TF_LOG_DIR}/${host_name}
    scp -r $ssh_opts heat-admin@$ip:logs/* ${TF_LOG_DIR}/${host_name}/
done

tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
