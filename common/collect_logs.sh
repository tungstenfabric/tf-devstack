function create_log_dir() {
    if [[ -z "$WORKSPACE" ]]; then
        echo "WORKSPACE must be set"
        return 1
    fi
    if [[ ! -d "$WORKSPACE" ]]; then
        echo "WORKSPACE must be set to an existing directory"
        return 1
    fi

    mkdir -p $WORKSPACE/logs
}

function collect_docker_logs() {
    echo "INFO: === Collecting docker logs ==="

    if [[ ! "$(sudo which docker)" ]]; then
        echo "INFO: There is no any docker installed"
        return 0
    fi

    mkdir -p $WORKSPACE/logs/docker/logs

    sudo docker ps -a > $WORKSPACE/logs/docker/docker-ps.txt
    containers="$(sudo docker ps -a --format '{{.ID}} {{.Names}}')"
    while read -r line
    do
        read -r -a params <<< "$line"
        echo "Save logs for ${params[1]}"
        sudo docker logs ${params[0]} &> $WORKSPACE/logs/docker/logs/${params[1]}.log
        sudo docker inspect ${params[0]} &> $WORKSPACE/logs/docker/logs/${params[1]}.inspect
    done <<< "$containers"

    sudo chown -R $USER $WORKSPACE/logs/docker
}

function collect_contrail_status() {
    echo "INFO: === Collecting contrail-status ==="
    sudo contrail-status > $WORKSPACE/logs/contrail-status
    sudo chown -R $USER $WORKSPACE/logs
}

function collect_system_stats() {
    echo "INFO: === Collecting system statistics for logs ==="

    syslogs="$WORKSPACE/logs/system"
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
    echo "INFO: === Collected juju status ==="

    local log_dir=$WORKSPACE/logs/

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
    echo "INFO: === Collecting juju logs ==="
    mkdir -p $WORKSPACE/logs/juju
    sudo cp -r /var/log/juju/* $WORKSPACE/logs/juju/ 2>/dev/null
    for ldir in "$HOME/logs" '/etc/apache2' '/etc/apt' '/etc/contrail' '/etc/contrailctl' '/etc/neutron' '/etc/nova' '/etc/haproxy' '/var/log/upstart' '/var/log/neutron' '/var/log/nova' '/var/log/contrail' '/etc/keystone' '/var/log/keystone' ; do
        if [ -d "$ldir" ] ; then
            echo "Save logs for $ldir"
            mkdir -p $WORKSPACE/logs/juju/$ldir
            sudo cp -r $ldir $WORKSPACE/logs/juju/$ldir
        fi
    done
    sudo chown -R $USER $WORKSPACE/logs/juju/
}

function collect_kubernetes_logs() {
    echo "INFO: === Collecting kubernetes logs ==="
    if [[ ! "$(sudo which kubectl)" ]]; then
        echo "INFO: There is no any kubernetes installed"
        return 0
    fi

    local KUBE_LOG_DIR=$WORKSPACE/logs/kubernetes_logs
    mkdir -p $KUBE_LOG_DIR

    declare -a namespaces
    namespages=`kubectl get namespaces -o name | awk -F '/' '{ print $2 }'`
    for namespace in $namespages ; do
        declare -a pods=`kubectl get pods -n ${namespace} -o name | awk -F '/' '{ print $2 }'`
        for pod in $pods ; do
            local init_containers=$(kubectl get pod $pod -n ${namespace} -o json -o jsonpath='{.spec.initContainers[*].name}')
            local containers=$(kubectl get pod $pod -n ${namespace} -o json -o jsonpath='{.spec.containers[*].name}')
            for container in ${init_containers} ${containers}; do
                echo "INFO: ${namespace}/${pod}/${container}"
                mkdir -p "$KUBE_LOG_DIR/pod-logs/${namespace}/${pod}"
                kubectl logs ${pod} -n ${namespace} -c ${container} > "$KUBE_LOG_DIR/pod-logs/${namespace}/${pod}/${container}.txt"
            done
        done
    done
}

function collect_kubernetes_objects_info() {
    echo "INFO: === Collecting kubernetes object info ==="
    if [[ ! "$(sudo which kubectl)" ]]; then
        echo "INFO: There is no any kubernetes installed"
        return 0
    fi

    local KUBE_OBJ_DIR=$WORKSPACE/logs/kubernetes_obj_info
    mkdir -p $KUBE_OBJ_DIR

    declare -a namespaces
    namespaces=$(kubectl get namespaces -o name | awk -F '/' '{ print $2 }')
    for namespace in $namespaces
    do
        echo namespace = $namespace
        declare -a objects_list
        objects_list=$(kubectl get -n ${namespace} pods -o name)
        for object in $objects_list
        do
            name=${object#*/}
            echo name = $name
            kubectl get -n ${namespace} pods ${name} -o yaml 1> ${KUBE_OBJ_DIR}/pod_${name}.txt 2> /dev/null
            kubectl describe -n ${namespace} pods ${name} 1> "${KUBE_OBJ_DIR}/desc_${name}.txt" 2> /dev/null
        done
    done
}