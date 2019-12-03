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
    echo "=== Collected docker logs ==="

    if [[ ! "$(sudo which docker)" ]]; then
        echo "There are no any docker installed"
        return 0
    fi

    create_log_dir
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