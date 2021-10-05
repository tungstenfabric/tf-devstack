#!/bin/bash -e

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"

source "$my_dir/../../../common/functions.sh"
source "$my_dir/../../definitions.sh"
source "$my_dir/../../functions.sh"
source "$my_dir/definitions"
source "$my_dir/functions"

start_ts=$(date +%s)

function err() {
    echo "ERROR: ${1}"
    exit 1
}

[[ -n "${OPENSHIFT_PULL_SECRET}" ]] || err "set OPENSHIFT_PULL_SECRET env variable"
[[ -n "${OPENSHIFT_PUB_KEY}" ]] || err "set OPENSHIFT_PUB_KEY env variable"

RHCOS_URL="${RHCOS_MIRROR}/${RHCOS_VERSION}/${RHCOS_IMAGE}"

controller_count=$(echo $CONTROLLER_NODES | wc -w)
agent_count=0
if [[ "$AGENT_NODES" != "$NODE_IP" ]] ; then
  # if AGENT_NODES is not set common.sh sets it into NODE_IP
  agent_count=$(echo $AGENT_NODES | wc -w)
fi

# main part

[[ -d "$INSTALL_DIR"  ]] && rm -rf ${INSTALL_DIR}
mkdir -p ${INSTALL_DIR}
mkdir -p ${DOWNLOADS_DIR}

download_artefacts

prepare_rhcos_install

prepare_install_config

mkdir -p ${INSTALL_DIR}/openshift
mkdir -p ${INSTALL_DIR}/manifests

openshift-install --dir $INSTALL_DIR create manifests

if [[ -n "${OCP_MANIFESTS_DIR}" ]]; then
  cp ${OCP_MANIFESTS_DIR}/* ${INSTALL_DIR}/manifests
else
  $OPENSHIFT_REPO/scripts/apply_install_manifests.sh ${INSTALL_DIR}
fi

# if no agents nodes - masters are schedulable, no needs patch ingress to re-schedule it on masters
if (( agent_count != 0 )) ; then
  masters_schedulable='false'
else
  masters_schedulable='true'
fi
sed -i -E "s/mastersSchedulable: .*/mastersSchedulable: $masters_schedulable/" ${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml

openshift-install create ignition-configs --dir=${INSTALL_DIR}

mgmt_net=$(echo $VIRTUAL_NET | cut -d ',' -f 1)
for i in ${VIRTUAL_NET//,/ } ; do
  sudo virsh net-define ${my_dir}/$i.xml
  sudo virsh net-autostart $i
  sudo virsh net-start $i
done

WS_PORT="1234"
cat <<EOF > tmpws.service
[Unit]
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt
ExecStart=/usr/bin/python -m SimpleHTTPServer ${WS_PORT}
[Install]
WantedBy=default.target
EOF

create_haproxy_cfg $WORKSPACE/haproxy.cfg

sudo cp "${DOWNLOADS_DIR}/CentOS-7-x86_64-GenericCloud.qcow2" "${LIBVIRT_DIR}/${KUBERNETES_CLUSTER_NAME}-lb.qcow2"

sudo virt-customize -a "${LIBVIRT_DIR}/${KUBERNETES_CLUSTER_NAME}-lb.qcow2" \
    --uninstall cloud-init --ssh-inject ${LB_SSH_USER}:file:${OPENSHIFT_PUB_KEY} --selinux-relabel --install haproxy --install bind-utils \
    --copy-in ${INSTALL_DIR}/bootstrap.ign:/opt/ --copy-in ${INSTALL_DIR}/master.ign:/opt/ --copy-in ${INSTALL_DIR}/worker.ign:/opt/ \
    --copy-in "${DOWNLOADS_DIR}/${RHCOS_IMAGE}":/opt/ --copy-in tmpws.service:/etc/systemd/system/ \
    --copy-in $WORKSPACE/haproxy.cfg:/etc/haproxy/ \
    --run-command "systemctl daemon-reload" --run-command "systemctl enable tmpws.service"

start_lb_vm ${KUBERNETES_CLUSTER_NAME}-lb "${LIBVIRT_DIR}/${KUBERNETES_CLUSTER_NAME}-lb.qcow2,cache=writeback,bus=virtio" ${LOADBALANCER_MEM} ${LOADBALANCER_CPU} "52:54:00:13:21:01"

ip_mac=( $(get_ip_mac ${KUBERNETES_CLUSTER_NAME}-lb) )
LBIP=${ip_mac[0]}

# Create machines
echo "INFO: start bootstrap vm"
start_openshift_vm ${KUBERNETES_CLUSTER_NAME}-bootstrap ${BOOTSTRAP_MEM} ${BOOTSTRAP_CPU} bootstrap "52:54:00:13:21:02"

for i in $(seq 1 ${controller_count}); do
  echo "INFO: start master-$i vm"
  start_openshift_vm ${KUBERNETES_CLUSTER_NAME}-master-${i} ${MASTER_MEM} ${MASTER_CPU} master "52:54:00:13:31:0${i}"
done

for i in $(seq 1 ${agent_count}); do
  echo "INFO: start worker-$i vm"
  start_openshift_vm ${KUBERNETES_CLUSTER_NAME}-worker-${i} ${WORKER_MEM} ${WORKER_CPU} worker "52:54:00:13:41:0${i}"
done

# Resstarting libvirt and dnsmasq
sudo systemctl restart libvirtd
sudo systemctl restart dnsmasq

# Configuring haproxy in LB VM
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}" "semanage port -a -t http_port_t -p tcp 6443" || \
    err "semanage port -a -t http_port_t -p tcp 6443 failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}" "semanage port -a -t http_port_t -p tcp 22623" || \
    err "semanage port -a -t http_port_t -p tcp 22623 failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}" "systemctl start haproxy" || \
    err "systemctl start haproxy failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}" "systemctl -q enable haproxy" || \
    err "systemctl enable haproxy failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}" "systemctl -q is-active haproxy" || \
    err "haproxy not working as expected"

bootstrap_finished ${KUBERNETES_CLUSTER_NAME}-bootstrap

# Waiting for SSH access on Boostrap VM
echo "INFO: wait for SSH to bootstrap vm"
wait_cmd_success "ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS core@bootstrap.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN} true" 10 20

for i in $(seq 1 ${controller_count}); do
  bootstrap_finished ${KUBERNETES_CLUSTER_NAME}-master-${i}
  # supposed that https://gerrit.tungsten.io/r/c/tungstenfabric/tf-openshift/+/64366 should fix
  # firstboot_wa master-${i}.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}
done

for i in $(seq 1 ${agent_count}); do
  bootstrap_finished ${KUBERNETES_CLUSTER_NAME}-worker-${i}
  # supposed that https://gerrit.tungsten.io/r/c/tungstenfabric/tf-openshift/+/64366 should fix
  # firstboot_wa worker-${i}.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}
done
