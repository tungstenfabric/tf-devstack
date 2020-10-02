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

    sudo chown -R $SUDO_UID:$SUDO_GID $TF_LOG_DIR/docker
}

function collect_contrail_status() {
    echo "INFO: Collecting contrail-status"
    mkdir -p $TF_LOG_DIR
    sudo contrail-status &> $TF_LOG_DIR/contrail-status
    sudo chown -R $SUDO_UID:$SUDO_GID $TF_LOG_DIR
}

function collect_kolla_logs() {
    echo "INFO: Collecting kolla logs"

    local log_dir="$TF_LOG_DIR/openstack"
    mkdir -p $log_dir

    if sudo ls /etc/kolla ; then
        sudo cp -R /etc/kolla $log_dir/
        sudo mv $log_dir/kolla $log_dir/kolla_etc
    fi

    local kl_path='/var/lib/docker/volumes/kolla_logs/_data'
    if sudo ls $kl_path ; then
        mkdir -p $log_dir/kolla_logs
        for ii in `sudo ls $kl_path/`; do
            sudo cp -R "$kl_path/$ii" $log_dir/kolla_logs/
        done
    fi

    sudo chown -R $SUDO_UID:$SUDO_GID $log_dir
    sudo find $log_dir -type f -exec chmod a+r {} \;
    sudo find $log_dir -type d -exec chmod a+rx {} \;
}

function collect_openstack_logs() {
    echo "INFO: Collecting openstack logs"

    local log_dir="$TF_LOG_DIR/openstack"
    mkdir -p $log_dir
    local ldir
    for ldir in '/etc/nova' '/var/log/nova' '/var/lib/config-data/puppet-generated/nova' '/var/log/containers/nova' \
                '/etc/haproxy' '/var/log/upstart' \
                '/etc/neutron' '/var/log/neutron' '/var/lib/config-data/puppet-generated/neutron' '/var/log/containers/neutron' \
                '/etc/keystone' '/var/log/keystone' '/var/lib/config-data/puppet-generated/keystone' '/var/log/containers/keystone' \
                '/etc/heat' '/var/log/heat' '/var/lib/config-data/puppet-generated/heat' '/var/log/containers/heat' \
                '/etc/glance' '/var/log/glance' '/var/lib/config-data/puppet-generated/glance' '/var/log/containers/glance' \
                '/etc/octavia' '/var/log/octavia' '/var/lib/config-data/puppet-generated/octavia' '/var/log/containers/octavia' \
                ; do
        if sudo ls "$ldir" ; then
            sudo cp -R $ldir $log_dir/
        fi
    done

    sudo chown -R $SUDO_UID:$SUDO_GID $log_dir
    sudo find $log_dir -type f -exec chmod a+r {} \;
    sudo find $log_dir -type d -exec chmod a+rx {} \;
}

function collect_contrail_logs() {
    echo "INFO: Collecting contrail logs"

    local log_dir="$TF_LOG_DIR/contrail"
    mkdir -p $log_dir

    if sudo ls /etc/contrail >/dev/null 2>&1 ; then
        echo "INFO: Collecting contrail logs: /etc/contrail"
        sudo cp -R /etc/contrail $log_dir/etc_contrail
    fi
    if sudo ls /etc/cni >/dev/null 2>&1 ; then
        echo "INFO: Collecting contrail logs: /etc/cni"
        sudo cp -R /etc/cni $log_dir/etc_cni
    fi

    local cl_path
    for cl_path in '/var/log/contrail' '/var/log/containers/contrail' ; do
        if sudo ls $cl_path >/dev/null 2>&1 ; then
            mkdir -p $log_dir/contrail_logs
            for ii in `sudo ls $cl_path/`; do
                echo "INFO: Collecting contrail logs: $cl_path/$ii"
                sudo cp -R "$cl_path/$ii" $log_dir/contrail_logs/
            done
        fi
    done

    mkdir -p $log_dir/introspect
    local url=$(hostname -f)
    local ssl_opts=''
    local proto='http'
    if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
        proto='https'
        ssl_opts="--key /etc/contrail/ssl/private/server-privkey.pem"
        ssl_opts+=" --cert /etc/contrail/ssl/certs/server.pem"
        ssl_opts+=" --cacert /etc/contrail/ssl/certs/ca-cert.pem"
    fi
    echo "INFO: Collecting contrail logs: save_introspect_info"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortConfigNodemgr 8100 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortControlNodemgr 8101 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortVRouterNodemgr 8102 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortDatabaseNodemgr 8103 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortAnalyticsNodemgr 8104 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortKubeManager 8108 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortConfigDatabaseNodemgr 8112 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortAnalyticsAlarmNodemgr 8113 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortAnalyticsSNMPNodemgr 8114 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortDeviceManagerNodemgr 8115 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortControl 8083 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortApiServer 8084 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortAgent 8085 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortSchemaTransformer 8087 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortSvcMonitor 8088 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortDeviceManager 8096 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortCollector 8089 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortOpserver 8090 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortQueryEngine 8091 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortDns 8092 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortAlarmGenerator 5995 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortSnmpCollector 5920 "$ssl_opts"
    save_introspect_info $log_dir/introspect ${proto}://$url HttpPortTopology 5921 "$ssl_opts"

    sudo chown -R $SUDO_UID:$SUDO_GID $log_dir
    sudo find $log_dir -type f -exec chmod a+r {} \;
    sudo find $log_dir -type d -exec chmod a+rx {} \;
}

function save_introspect_info() {
    if sudo lsof -i ":$4" &>/dev/null ; then
        echo "INFO: Collecting contrail logs: introspection request: curl -s $5 $2:$4/Snh_SandeshUVECacheReq?x=NodeStatus"
        sudo timeout -s 9 30 curl -s $5 $2:$4/Snh_SandeshUVECacheReq?x=NodeStatus > $1/$3.xml.log
    fi
}

function collect_system_stats() {
    local host_name=${1:-}
    echo "INFO: Collecting system statistics for logs"
    local syslogs="$TF_LOG_DIR"
    [ -z "$host_name" ] || syslogs+="/${host_name}"
    syslogs+="/system"
    mkdir -p "$syslogs"
    ps ax -H &> $syslogs/ps.log
    sudo netstat -lpn &> $syslogs/netstat.log
    free -h &> $syslogs/mem.log
    df -h &> $syslogs/df.log
    ifconfig &>$syslogs/if.log
    ip addr &>$syslogs/ip_addr.log
    ip link &>$syslogs/ip_link.log
    ip route &>$syslogs/ip_route.log
    cat /etc/hosts &>$syslogs/etc_hosts
    cat /etc/resolv.conf &>$syslogs/etc_resolv.conf
    ls -la /etc/ &>$syslogs/ls_etc.log
    if [ -e /var/log/messages ] ; then
        yes | sudo cp /var/log/messages* $syslogs/
    fi
    if [ -e /var/log/syslog ] ; then
        yes | sudo cp /var/log/syslog* $syslogs/
    fi
    if which vif &>/dev/null ; then
        sudo vif --list &>$syslogs/vif.log
    fi
    sudo dmesg &> $syslogs/dmesg.log
    sudo chown -R $SUDO_UID:$SUDO_GID $syslogs
    sudo find $syslogs -type f -exec chmod a+r {} \;
    sudo find $syslogs -type d -exec chmod a+rx {} \;
}

function collect_juju_status() {
    echo "INFO: Collected juju status"

    local log_dir="$TF_LOG_DIR/juju"
    mkdir -p "$log_dir"

    echo "INFO: Save juju statuses to logs"
    timeout -s 9 30 juju status --format yaml > $log_dir/juju_status.log
    timeout -s 9 30 juju status --format tabular > $log_dir/juju_status_tabular.log

    echo "INFO: Save current juju configuration to logs"
    command juju export-bundle > $log_dir/bundle.yaml

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
    sudo chown -R $SUDO_UID:$SUDO_GID $TF_LOG_DIR/juju/
    sudo find $TF_LOG_DIR/juju/ -type f -exec chmod a+r {} \;
}

function collect_kubernetes_logs() {
    echo "INFO: Collecting kubernetes logs"
    if ! which kubectl &>/dev/null ; then
        echo "INFO: There is no any kubernetes installed"
        return 0
    fi

    local KUBE_LOG_DIR=$TF_LOG_DIR/kubernetes_logs
    mkdir -p $KUBE_LOG_DIR

    local namespace=''
    local namespaces=`kubectl get namespaces -o name | awk -F '/' '{ print $2 }'`
    for namespace in $namespaces ; do
        local pod=''
        local pods=`kubectl get pods -n ${namespace} -o name | awk -F '/' '{ print $2 }'`
        for pod in $pods ; do
            local init_containers=$(kubectl get pod $pod -n ${namespace} -o json -o jsonpath='{.spec.initContainers[*].name}')
            local containers=$(kubectl get pod $pod -n ${namespace} -o json -o jsonpath='{.spec.containers[*].name}')
            for container in $init_containers $containers; do
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

    kubectl get namespaces > $TF_LOG_DIR/kubernetes_namespaces
    kubectl get nodes -o wide > $TF_LOG_DIR/kubernetes_nodes
    kubectl get all --all-namespaces > $TF_LOG_DIR/kubernetes_all

    local namespace=''
    local namespaces=$(kubectl get namespaces -o name | awk -F '/' '{ print $2 }')
    for namespace in $namespaces ; do
        local object=''
        local objects_list=$(kubectl get -n ${namespace} pods -o name)
        for object in $objects_list ; do
            local name=${object#*/}
            kubectl get -n ${namespace} pods ${name} -o yaml 1> ${KUBE_OBJ_DIR}/pod_${name}.txt 2> /dev/null
            kubectl describe -n ${namespace} pods ${name} 1> "${KUBE_OBJ_DIR}/desc_${name}.txt" 2> /dev/null
        done
    done
}

if [[ "${0}" == *"collect_logs.sh" ]] && [[ -n "${1}" ]]; then
   $1
fi
