# This can be used in 2 ways:
# 1) including as library (source common/collect_logs.sh; collect_docker_logs)
# 2) running as script (../common/collect_logs.sh collect_docker_logs)

function init_output_logging {
  if [[ -n "$TF_LOG_DIR" ]]; then
    mkdir -p $TF_LOG_DIR
    exec &> >(tee -a "${TF_LOG_DIR}/output.log")
    echo "INFO: =================== $(date) ==================="
  else
    echo "WARNING: TF_LOG_DIR is not set. output.log is not collected"
  fi
}

function create_log_dir() {
    if [[ -z "$TF_LOG_DIR" ]]; then
        echo "TF_LOG_DIR must be set"
        return 1
    fi

    mkdir -p $TF_LOG_DIR
}

function collect_docker_logs() {
    echo "INFO: Collecting docker logs"

    if ! which docker &>/dev/null ; then
        echo "INFO: There is no any docker installed"
        return 0
    fi

    local log_dir="$TF_LOG_DIR/docker"
    mkdir -p $log_dir

    sudo docker ps -a > $log_dir/__docker-ps.txt
    sudo docker images > $log_dir/__docker-images.txt
    sudo docker volume ls > $log_dir/__docker-volumes.txt
    local containers="$(sudo docker ps -a --format '{{.ID}} {{.Names}}')"
    local line
    local params
    while read -r line
    do
        read -r -a params <<< "$line"
        sudo docker logs ${params[0]} &> $log_dir/${params[1]}.log
        sudo docker inspect ${params[0]} &> $log_dir/${params[1]}.inspect
    done <<< "$containers"

    sudo chown -R $USER $TF_LOG_DIR/docker
}

function collect_contrail_status() {
    echo "INFO: Collecting contrail-status"
    sudo contrail-status &> $TF_LOG_DIR/contrail-status
    sudo chown -R $USER $TF_LOG_DIR
}

function collect_contrail_logs() {
    echo "INFO: Collecting contrail logs"

    local log_dir="$TF_LOG_DIR/contrail"
    mkdir -p $log_dir

    if [ -d /etc/contrail ]; then
        mkdir -p $log_dir/etc_contrail
        sudo cp -R /etc/contrail $log_dir/etc_contrail/
    fi
    if [ -d /etc/cni ]; then
        mkdir -p $log_dir/etc_cni
        sudo cp -R /etc/cni $log_dir/etc_cni/
    fi
    if [ -d /etc/kolla ]; then
        mkdir -p $log_dir/kolla_etc
        sudo cp -R /etc/kolla $log_dir/kolla_etc/
    fi

    local kl_path='/var/lib/docker/volumes/kolla_logs/_data'
    if [ -d $kl_path ]; then
        mkdir -p $log_dir/kolla_logs
        for ii in `ls $kl_path/`; do
            sudo cp -R "$kl_path/$ii" $log_dir/kolla_logs/
        done
    fi

    local cl_path='/var/log/contrail'
    if [ -d $cl_path ]; then
        mkdir -p $log_dir/contrail_logs
        for ii in `ls $cl_path/`; do
            sudo cp -R "$cl_path/$ii" $log_dir/contrail_logs/
        done
    fi

    mkdir -p $log_dir/introspect
    local url=$(hostname -f)
    save_introspect_info $log_dir/introspect $url HttpPortConfigNodemgr 8100
    save_introspect_info $log_dir/introspect $url HttpPortControlNodemgr 8101
    save_introspect_info $log_dir/introspect $url HttpPortVRouterNodemgr 8102
    save_introspect_info $log_dir/introspect $url HttpPortDatabaseNodemgr 8103
    save_introspect_info $log_dir/introspect $url HttpPortAnalyticsNodemgr 8104
    save_introspect_info $log_dir/introspect $url HttpPortKubeManager 8108
    #save_introspect_info $log_dir $url HttpPortMesosManager 8109
    save_introspect_info $log_dir/introspect $url HttpPortConfigDatabaseNodemgr 8112
    save_introspect_info $log_dir/introspect $url HttpPortAnalyticsAlarmNodemgr 8113
    save_introspect_info $log_dir/introspect $url HttpPortAnalyticsSNMPNodemgr 8114
    save_introspect_info $log_dir/introspect $url HttpPortDeviceManagerNodemgr 8115
    save_introspect_info $log_dir/introspect $url HttpPortControl 8083
    save_introspect_info $log_dir/introspect $url HttpPortApiServer 8084
    save_introspect_info $log_dir/introspect $url HttpPortAgent 8085
    save_introspect_info $log_dir/introspect $url HttpPortSchemaTransformer 8087
    save_introspect_info $log_dir/introspect $url HttpPortSvcMonitor 8088
    save_introspect_info $log_dir/introspect $url HttpPortDeviceManager 8096
    save_introspect_info $log_dir/introspect $url HttpPortCollector 8089
    save_introspect_info $log_dir/introspect $url HttpPortOpserver 8090
    save_introspect_info $log_dir/introspect $url HttpPortQueryEngine 8091
    save_introspect_info $log_dir/introspect $url HttpPortDns 8092
    save_introspect_info $log_dir/introspect $url HttpPortAlarmGenerator 5995
    save_introspect_info $log_dir/introspect $url HttpPortSnmpCollector 5920
    save_introspect_info $log_dir/introspect $url HttpPortTopology 5921

    sudo chown -R $USER $log_dir
    sudo chmod -R a+rw $log_dir
}

function save_introspect_info() {
    if sudo lsof -i ":$4" &>/dev/null ; then
        timeout -s 9 30 curl -s http://$2:$4/Snh_SandeshUVECacheReq?x=NodeStatus > $1/$3.xml.log
    fi
}

function collect_system_stats() {
    echo "INFO: Collecting system statistics for logs"

    syslogs="$TF_LOG_DIR/system"
    mkdir -p "$syslogs"
    ps ax -H &> $syslogs/ps.log
    netstat -lpn &> $syslogs/netstat.log
    free -h &> $syslogs/mem.log
    df -h &> $syslogs/df.log
    ifconfig &>$syslogs/if.log
    ip addr &>$syslogs/ip_addr.log
    ip link &>$syslogs/ip_link.log
    ip route &>$syslogs/ip_route.log

    if which vif &>/dev/null ; then
        sudo vif --list &>$syslogs/vif.log
    fi
    sudo chown -R $USER $syslogs
}

function collect_juju_status() {
    echo "INFO: Collected juju status"

    local log_dir="$TF_LOG_DIR/juju"
    mkdir -p "$log_dir"

    echo "INFO: Save juju statuses to logs"
    timeout -s 9 30 juju status --format yaml > $log_dir/juju_status.log
    timeout -s 9 30 juju status --format tabular > $log_dir/juju_status_tabular.log

    echo "INFO: Save current juju configuration to logs"
    command juju export-bundle --filename $log_dir/bundle.yaml

    echo "INFO: Save unit statuses to logs"
    for unit in `timeout -s 9 30 juju status $juju_model_arg --format oneline | awk '{print $2}' | sed 's/://g'` ; do
        if [[ -z "$unit" || "$unit" =~ "ubuntu/" || "$unit" =~ "ntp/" ]] ; then
            continue
        fi
      echo "INFO: --------------------------------- $unit statuses log" >> $log_dir/juju_unit_statuses.log
      command juju show-status-log $juju_model_arg --days 1 $unit >> $log_dir/juju_unit_statuses.log
    done
}

function collect_juju_logs() {
    echo "INFO: Collecting juju logs"
    mkdir -p $TF_LOG_DIR/juju
    sudo cp -r /var/log/juju/* $TF_LOG_DIR/juju/ 2>/dev/null
    sudo chown -R $USER $TF_LOG_DIR/juju/
}

function collect_kubernetes_logs() {
    echo "INFO: Collecting kubernetes logs"
    if ! which kubectl &>/dev/null ; then
        echo "INFO: There is no any kubernetes installed"
        return 0
    fi

    local KUBE_LOG_DIR=$TF_LOG_DIR/kubernetes_logs
    mkdir -p $KUBE_LOG_DIR

    declare -a namespaces
    namespages=`kubectl get namespaces -o name | awk -F '/' '{ print $2 }'`
    for namespace in $namespages ; do
        declare -a pods=`kubectl get pods -n ${namespace} -o name | awk -F '/' '{ print $2 }'`
        for pod in $pods ; do
            local init_containers=$(kubectl get pod $pod -n ${namespace} -o json -o jsonpath='{.spec.initContainers[*].name}')
            local containers=$(kubectl get pod $pod -n ${namespace} -o json -o jsonpath='{.spec.containers[*].name}')
            for container in ${init_containers} ${containers}; do
                mkdir -p "$KUBE_LOG_DIR/pod-logs/${namespace}/${pod}"
                kubectl logs ${pod} -n ${namespace} -c ${container} > "$KUBE_LOG_DIR/pod-logs/${namespace}/${pod}/${container}.txt"
            done
        done
    done
}

function collect_kubernetes_objects_info() {
    echo "INFO: Collecting kubernetes object info"
    if ! which kubectl &>/dev/null ; then
        echo "INFO: There is no any kubernetes installed"
        return 0
    fi

    local KUBE_OBJ_DIR=$TF_LOG_DIR/kubernetes_obj_info
    mkdir -p $KUBE_OBJ_DIR

    declare -a namespaces
    namespaces=$(kubectl get namespaces -o name | awk -F '/' '{ print $2 }')
    for namespace in $namespaces
    do
        declare -a objects_list
        objects_list=$(kubectl get -n ${namespace} pods -o name)
        for object in $objects_list
        do
            name=${object#*/}
            kubectl get -n ${namespace} pods ${name} -o yaml 1> ${KUBE_OBJ_DIR}/pod_${name}.txt 2> /dev/null
            kubectl describe -n ${namespace} pods ${name} 1> "${KUBE_OBJ_DIR}/desc_${name}.txt" 2> /dev/null
        done
    done
}

if [[ "${0}" == *"collect_logs.sh" ]] && [[ -n "${1}" ]]; then
   $1
fi

