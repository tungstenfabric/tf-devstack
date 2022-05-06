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
  mkdir -p ${DOWNLOADS_DIR}

  if [[ ! -f ${DOWNLOADS_DIR}/${CLIENT} ]]; then
    echo "INFO: download $CLIENT_URL"
    wget -nv "$CLIENT_URL" -O "${DOWNLOADS_DIR}/$CLIENT"
    tar -xf "${DOWNLOADS_DIR}/${CLIENT}"
    rm -f README.md
  fi

  if [[ "${OPENSHIFT_AI_INSTALLER,,}" != 'true' ]]; then
    if [[ ! -f ${DOWNLOADS_DIR}/${INSTALLER} ]]; then
      echo "INFO: download $INSTALLER_URL"
      wget -nv "$INSTALLER_URL" -O "${DOWNLOADS_DIR}/$INSTALLER"
      tar -xf "${DOWNLOADS_DIR}/${INSTALLER}"
      rm -f README.md
    fi
  fi

  if [[ "$PROVIDER" == "kvm" ]]; then
    local rhcos_base_url="${RHCOS_MIRROR}/${OPENSHIFT_VERSION}/${RHCOS_VERSION}"
    local i
    for i in "${RHCOS_IMAGE}" "${RHCOS_KERNEL}" "${RHCOS_INITRAMFS}" ; do
      if [[ ! -f ${DOWNLOADS_DIR}/${i} ]]; then
        echo "INFO: download $rhcos_base_url/${i}"
        wget -nv "$rhcos_base_url/${i}" -O "${DOWNLOADS_DIR}/${i}"
      fi
    done
    if [[ ! -f ${DOWNLOADS_DIR}/${LB_IMAGE} ]]; then
      echo "INFO: download $LB_IMG_URL"
      wget -nv "$LB_IMG_URL" -O "${DOWNLOADS_DIR}/$LB_IMAGE"
    fi
  fi
}

function kubeconfig_copy() {
  mkdir -p ~/.kube
  cp ${KUBECONFIG} ~/.kube/config
  chmod go-rwx ~/.kube/config
}

function prepare_rhcos_install() {
  local d="${INSTALL_DIR}/rhcos-install"
  mkdir -p $d
  cp "${DOWNLOADS_DIR}/${RHCOS_KERNEL}" "$d/vmlinuz"
  cp "${DOWNLOADS_DIR}/${RHCOS_INITRAMFS}" "$d/initramfs.img"
  cat <<EOF > $d/.treeinfo
[general]
arch = x86_64
family = Red Hat CoreOS
platforms = x86_64
version = ${OCP_VER}
[images-x86_64]
initrd = initramfs.img
kernel = vmlinuz
EOF
}

function prepare_install_config() {
  local controller_count=$(echo $CONTROLLER_NODES | wc -w)
  if [ -z "$controller_count" ] ; then
    echo "ERROR: internal error controller_count must be set"
    exit 1
  fi
  local jinja="$my_dir/../common/jinja2_render.py"
  $jinja < $my_dir/install_config.yaml.j2 > $INSTALL_DIR/install-config.yaml
  cat $INSTALL_DIR/install-config.yaml
}

function patch_ingress_controller() {
  # By default ingress is scheduled in workers which requires rules in haproxy
  # that makes more difficult to CI to manage it.
  # So, patch ingress to re-schedule it on masters
  local controller_count=$1
  oc patch ingresscontroller default -n openshift-ingress-operator \
    --type merge \
    --patch '{
      "spec": {
        "replicas": '${controller_count}',
        "nodePlacement": {
          "nodeSelector": {
            "matchLabels": {
              "node-role.kubernetes.io/master":""
            }
          },
          "tolerations":[{
            "effect": "NoSchedule",
            "operator": "Exists"
          }]
        }
      }
    }'
}

function monitor_csr() {
  local csr
  while true; do
    for csr in $(oc get csr 2> /dev/null | grep -w 'Pending' | awk '{print $1}'); do
      echo "INFO: csr monitor: approve $csr"
      oc adm certificate approve "$csr" 2> /dev/null || true
    done
    sleep 5
  done
}

function wait_vhost0_up() {
    local node
    for node in $(echo ${CONTROLLER_NODES} ${AGENT_NODES} | tr ',' ' ') ; do
        scp $SSH_OPTIONS ${fmy_dir}/functions.sh ${node}:/tmp/functions.sh
        if ! ssh $SSH_OPTIONS ${node} "export PATH=\$PATH:/usr/sbin ; source /tmp/functions.sh ; wait_nic_up vhost0" ; then
            return 1
        fi
    done
}

