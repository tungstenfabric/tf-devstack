#!/bin/bash

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

# TODO: remove
# temporary reload common check_pods_active to pass webui1-webui-statefulset pod while it isn't ready
# will be removed later
function check_pods_active() {
  declare -a pods
  readarray -t pods < <(kubectl get pods --all-namespaces --no-headers)

  if [[ ${#pods[@]} == '0' ]]; then
    return 1
  fi

  #check if all pods are running
  for pod in "${pods[@]}" ; do
    local pod_name="$(echo $pod | awk '{print $2}')"
    if [[ "$pod_name" == *'webui'* ]]; then
      continue
    fi
    local status="$(echo $pod | awk '{print $4}')"
    if [[ "$status" == 'Completed' ]]; then
      continue
    elif [[ "$status" != "Running" ]] ; then
      return 1
    else
      local containers_running=$(echo $pod  | awk '{print $3}' | cut  -f1 -d/ )
      local containers_total=$(echo $pod  | awk '{print $3}' | cut  -f2 -d/ )
      if [ "$containers_running" != "$containers_total" ] ; then
        return 1
      fi
    fi
  done
  return 0
}
