#!/bin/bash

function collect_logs_from_machines() {

    collect_kubernetes_objects_info oc
    collect_kubernetes_logs oc
    collect_kubernetes_service_statuses oc

    cat <<EOF >/tmp/logs.sh
#!/bin/bash
tgz_name=\$1
export WORKSPACE=/tmp/openshift-logs
export TF_LOG_DIR=/tmp/openshift-logs/logs
export DEPLOYER=$DEPLOYER
export SSL_ENABLE=$SSL_ENABLE
cd /tmp/openshift-logs
source ./collect_logs.sh
collect_system_stats
collect_tf_status
collect_docker_logs crictl
collect_tf_logs
sudo chmod -R a+r logs
pushd logs
tar -czf \$tgz_name *
popd
cp logs/\$tgz_name \$tgz_name
sudo rm -rf logs
EOF
    chmod a+x /tmp/logs.sh

    export CONTROLLER_NODES="` | tr '\n' ','`"
    echo "INFO: controller_nodes: $CONTROLLER_NODES"
    export AGENT_NODES="`oc get nodes -o wide | awk '/ worker /{print $6}' | tr '\n' ','`"

    local machine
    for machine in $(oc get nodes -o wide --no-headers | awk '{print $6}' | sort -u) ; do
        local ssh_dest="core@$machine"
        local tgz_name="logs-$machine.tgz"
        mkdir -p $TF_LOG_DIR/$machine
        ssh $SSH_OPTS $ssh_dest "mkdir -p /tmp/openshift-logs"
        scp $SSH_OPTS $my_dir/../common/collect_logs.sh $ssh_dest:/tmp/openshift-logs/collect_logs.sh
        scp $SSH_OPTS /tmp/logs.sh $ssh_dest:/tmp/openshift-logs/logs.sh
        ssh $SSH_OPTS $ssh_dest /tmp/openshift-logs/logs.sh $tgz_name
        scp $SSH_OPTS $ssh_dest:/tmp/openshift-logs/$tgz_name $TF_LOG_DIR/$machine/
        pushd $TF_LOG_DIR/$machine/
        tar -xzf $tgz_name
        rm -rf $tgz_name
        popd
    done
}

function download_artefacts() {
  [[ ! -d ${DOWNLOADS_DIR} ]] && mkdir -p ${DOWNLOADS_DIR}

  if [[ ! -f ${DOWNLOADS_DIR}/${CLIENT} ]]; then
    wget -nv "$CLIENT_URL" -O "${DOWNLOADS_DIR}/$CLIENT"
    tar -xf "${DOWNLOADS_DIR}/${CLIENT}"
    rm -f README.md
  fi
  if [[ ! -f ${DOWNLOADS_DIR}/${INSTALLER} ]]; then
    wget -nv "$INSTALLER_URL" -O "${DOWNLOADS_DIR}/$INSTALLER"
    tar -xf "${DOWNLOADS_DIR}/${INSTALLER}"
    rm -f README.md
  fi

  if [[ "$PROVIDER" == "kvm" ]]; then
    if [[ ! -f ${DOWNLOADS_DIR}/${RHCOS_IMAGE} ]]; then
        wget -nv "$RHCOS_URL" -O "${DOWNLOADS_DIR}/${RHCOS_IMAGE}"
    fi
    if [[ ! -f ${DOWNLOADS_DIR}/${RHCOS_KERNEL} ]]; then
        wget -nv "${RHCOS_MIRROR}/${RHCOS_VERSION}/$RHCOS_KERNEL" -O "${DOWNLOADS_DIR}/$RHCOS_KERNEL"
    fi
    if [[ ! -f ${DOWNLOADS_DIR}/${RHCOS_INITRAMFS} ]]; then
        wget -nv "${RHCOS_MIRROR}/${RHCOS_VERSION}/$RHCOS_INITRAMFS" -O "${DOWNLOADS_DIR}/$RHCOS_INITRAMFS"
    fi
    if [[ ! -f ${DOWNLOADS_DIR}/${LB_IMAGE} ]]; then
        wget -nv "$LB_IMG_URL" -O "${DOWNLOADS_DIR}/$LB_IMAGE"
    fi
  fi
}

function kubeconfig_copy() {
  mkdir -p ~/.kube
  cp ${KUBECONFIG} ~/.kube/config
  chmod go-rwx ~/.kube/config
}