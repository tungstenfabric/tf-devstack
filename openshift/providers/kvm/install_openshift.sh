#!/bin/bash -e

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"

[ "${DEBUG,,}" == "true" ] && set -x

source "$my_dir/../../../common/functions.sh"
source "$my_dir/../../../contrib/infra/kvm/functions.sh"
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

controller_count=$(echo $CONTROLLER_NODES | wc -w)
agent_count=0
if [[ "$AGENT_NODES" != "$NODE_IP" ]] ; then
  # if AGENT_NODES is not set common.sh sets it into NODE_IP
  agent_count=$(echo $AGENT_NODES | wc -w)
fi

domain_suffix="${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}"

# main part
openshift-install --dir $INSTALL_DIR create manifests

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

start_lb

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
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${domain_suffix}" "semanage port -a -t http_port_t -p tcp 6443" || \
    err "semanage port -a -t http_port_t -p tcp 6443 failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${domain_suffix}" "semanage port -a -t http_port_t -p tcp 22623" || \
    err "semanage port -a -t http_port_t -p tcp 22623 failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${domain_suffix}" "systemctl start haproxy" || \
    err "systemctl start haproxy failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${domain_suffix}" "systemctl -q enable haproxy" || \
    err "systemctl enable haproxy failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${domain_suffix}" "systemctl -q is-active haproxy" || \
    err "haproxy not working as expected"

bootstrap_finished ${KUBERNETES_CLUSTER_NAME}-bootstrap

# Waiting for SSH access on Boostrap VM
echo "INFO: wait for SSH to bootstrap vm"
wait_cmd_success "ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS core@bootstrap.${domain_suffix} true" 10 20

names=""
for i in $(seq 1 ${controller_count}); do
  names+=" master-${i}"
  bootstrap_finished ${KUBERNETES_CLUSTER_NAME}-master-${i}
  # supposed that https://gerrit.tungsten.io/r/c/tungstenfabric/tf-openshift/+/64366 should fix
  # firstboot_wa master-${i}.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}
done

for i in $(seq 1 ${agent_count}); do
  bootstrap_finished ${KUBERNETES_CLUSTER_NAME}-worker-${i}
  # supposed that https://gerrit.tungsten.io/r/c/tungstenfabric/tf-openshift/+/64366 should fix
  # firstboot_wa worker-${i}.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}
done

# wait ssh for masters (workers are not available at this moment)
for i in $names ; do
  fn="core@${i}.${domain_suffix}"
  wait_ssh "$fn" $OPENSHIFT_SSH_KEY
  cat <<\EOF | ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS $fn
sudo usermod --password $(echo qwe123QWE | openssl passwd -1 -stdin) core
EOF
  cat <<\EOF | ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS $fn
sudo usermod --password $(echo qwe123QWE | openssl passwd -1 -stdin) root
EOF
done
