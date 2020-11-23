#!/bin/bash

# There are three fetch_deployer functions/methods now:
# - fetch_deployer_no_docker - the most advanced function - fetch deployer src container without installing docker. In the future she will replace all the others
# - fetch_deployer - function fetch deployer src container using docker. Needs docker to be installed on host
# - old_XXX_fetch_deployer - deprecated deployer method saved for backward compatibility. Will be removed in the future.

function old_k8s_fetch_deployer() {
    local deployer_image="contrail-k8s-manifests"
    local deployer_dir="$WORKSPACE/tf-container-builder"
    local image="$CONTAINER_REGISTRY/$deployer_image"
    sudo rm -rf $deployer_dir
    [ -n "$CONTRAIL_CONTAINER_TAG" ] && image+=":$CONTRAIL_CONTAINER_TAG"
    sudo docker create --name $deployer_image --entrypoint /bin/true $image
    sudo docker cp $deployer_image:contrail-container-builder $deployer_dir
    sudo docker rm -fv $deployer_image
}

function collect_logs_from_machines() {
    cat <<EOF >/tmp/logs.sh
#!/bin/bash
tgz_name=\$1
export WORKSPACE=/tmp/k8s_manifests-logs
export TF_LOG_DIR=/tmp/k8s_manifests-logs/logs
export SSL_ENABLE=$SSL_ENABLE
cd /tmp/k8s_manifests-logs
source ./collect_logs.sh
collect_system_stats
collect_contrail_status
collect_docker_logs
collect_kubernetes_objects_info
collect_kubernetes_logs
collect_contrail_logs
chmod -R a+r logs
pushd logs
tar -czf \$tgz_name *
popd
cp logs/\$tgz_name \$tgz_name
rm -rf logs
EOF
    chmod a+x /tmp/logs.sh

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local machine
    for machine in $(echo "$CONTROLLER_NODES $AGENT_NODES" | tr " " "\n" | sort -u) ; do
        local tgz_name="logs-$machine.tgz"
        mkdir -p $TF_LOG_DIR/$machine
        ssh $ssh_opts $machine "mkdir -p /tmp/k8s_manifests-logs"
        scp $ssh_opts $my_dir/../common/collect_logs.sh $machine:/tmp/k8s_manifests-logs/collect_logs.sh
        scp $ssh_opts /tmp/logs.sh $machine:/tmp/k8s_manifests-logs/logs.sh
        ssh $ssh_opts $machine /tmp/k8s_manifests-logs/logs.sh $tgz_name
        scp $ssh_opts $machine:/tmp/k8s_manifests-logs/$tgz_name $TF_LOG_DIR/$machine/
        pushd $TF_LOG_DIR/$machine/
        tar -xzf $tgz_name
        rm -rf $tgz_name
        popd
    done
}
