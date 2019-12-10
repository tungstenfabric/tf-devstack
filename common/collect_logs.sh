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
    echo "INFO: === Collected docker logs ==="

    if [[ ! "$(sudo which docker)" ]]; then
        echo "ERROR: There are no any docker installed"
        return 0
    fi

    mkdir -p $WORKSPACE/logs/docker/logs $WORKSPACE/logs/docker/inspects

    local docker_ps_file=$WORKSPACE/logs/docker/docker-ps.txt
    sudo docker ps -a --format '{{.ID}} {{.Names}} {{.Image}} "{{.Status}}"' > $docker_ps_file

    while read -r line
    do
        read -r -a params <<< "$line"
        echo "Save logs for ${params[1]}"
        sudo docker logs ${params[0]} &> $WORKSPACE/logs/docker/logs/${params[0]}_${params[1]}
        sudo docker inspect ${params[0]} &> $WORKSPACE/logs/docker/inspects/${params[0]}_${params[1]}

    done < "$docker_ps_file"

    sudo chown -R $USER $WORKSPACE/logs/docker
}

function collect_juju_logs() {
    echo "INFO: === Collected juju logs ==="

    local log_dir=$WORKSPACE/logs/juju
    mkdir $log_dir

    echo "INFO: Save juju statuses to logs"
    timeout -s 9 30 juju status --format yaml > $log_dir/juju_status.log
    timeout -s 9 30 juju status --format tabular > $log_dir/juju_status_tabular.log

    echo "INFO: Save current juju configuration to logs"
    juju export-bundle --filename $log_dir/bundle.yaml

    echo "INFO: Save unit statuses to logs"
    for unit in `timeout -s 9 30 juju status $juju_model_arg --format oneline | awk '{print $2}' | sed 's/://g'` ; do
        if [[ -z "$unit" || "$unit" =~ "ubuntu/" || "$unit" =~ "ntp/" ]] ; then
            continue
        fi
      echo "INFO: --------------------------------- $unit statuses log" >> $log_dir/juju_unit_statuses.log
      juju show-status-log $juju_model_arg --days 1 $unit >> $log_dir/juju_unit_statuses.log
    done

    echo "INFO: Save logs"
    for ldir in "$HOME/logs" '/etc/apache2' '/etc/apt' '/etc/contrail' '/etc/contrailctl' '/etc/neutron' '/etc/nova' '/etc/haproxy' '/var/log/upstart' '/var/log/neutron' '/var/log/nova' '/var/log/contrail' '/etc/keystone' '/var/log/keystone' ; do
        if [ -d "$ldir" ] ; then
            sudo cp -r $ldir $log_dir
        fi
    done
    sudo chown -R $USER $log_dir
}

function collect_kubernetes_logs() {
    echo "INFO: === Collected kubernetes logs ==="
    if [[ ! "$(sudo which kubectl)" ]]; then
        echo "ERROR: There are no any kubernetes installed"
        return 0
    fi

    mkdir -p $WORKSPACE/logs/kubernetes
    local KUBE_LOG_DIR=$WORKSPACE/logs/kubernetes

    declare -a namespaces
    namespages=`kubectl get namespaces -o name | awk -F '/' '{ print $2 }'`
    for namespace in $namespages
    do
        declare -a pods=`kubectl get pods -n ${namespace} -o name | awk -F '/' '{ print $2 }'`
        for pod in $pods
        do
            local init_containers=$(kubectl get pod $POD -n ${namespace} -o json | jq -r '.spec.initContainers[]?.name')
            local containers=$(kubectl get pod $pod -n ${namespace} -o json | jq -r '.spec.containers[].name')
            for container in ${init_containers} ${containers}; do
                echo "INFO: ${namespace}/${pod}/${container}"
                mkdir -p "$KUBE_LOG_DIR/pod-logs/${namespace}/${pod}"
                kubectl logs ${pod} -n ${namespace} -c ${container} > "$KUBE_LOG_DIR/pod-logs/${namespace}/${pod}/${container}.txt"
            done
        done
    done    

}
