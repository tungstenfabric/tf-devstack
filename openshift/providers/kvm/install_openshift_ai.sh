#!/bin/bash -e

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"

[ "${DEBUG,,}" == "true" ] && set -x

source "$my_dir/../../../common/functions.sh"
source "$my_dir/../../definitions.sh"
source "$my_dir/../../functions.sh"
source "$my_dir/definitions"
source "$my_dir/functions"
source "$my_dir/../../../contrib/infra/kvm/functions.sh"

export PATH=$PATH:$HOME

if [[ -z "${AI_OFFLINE_TOKEN}" && "${OPENSHIFT_AI_DISABLE_SSO}" != "true" ]]; then
  echo "ERROR: Set offline token before call openshift API"
  exit 1
fi

controller_count=$(echo $CONTROLLER_NODES | wc -w)
agent_count=0
if [[ "$AGENT_NODES" != "$NODE_IP" ]] ; then
  # if AGENT_NODES is not set common.sh sets it into NODE_IP
  agent_count=$(echo $AGENT_NODES | wc -w)
fi

mgmt_net=$(echo $VIRTUAL_NET | cut -d ',' -f 1)
for i in ${VIRTUAL_NET//,/ } ; do
  sudo virsh net-define ${my_dir}/$i.xml
  sudo virsh net-autostart $i
  sudo virsh net-start $i
done

start_lb

lb_ip=$(get_ip_mac ${KUBERNETES_CLUSTER_NAME}-lb | awk '{print $1}')
install_ai_service $lb_ip
OPENSHIFT_AI_API_BASE=http://${lb_ip}:8090/api/assisted-install
OPENSHIFT_AI_API_V1="${OPENSHIFT_AI_API_BASE}/v1"
OPENSHIFT_AI_API_V2="${OPENSHIFT_AI_API_BASE}/v2"

# Get auth token
if [[ "${OPENSHIFT_AI_DISABLE_SSO}" != "true" && -z "$OPENSHIFT_AI_SSO_TOKEN" ]]; then
  OPENSHIFT_AI_SSO_TOKEN="$(ai_get_access_token)"
fi

cluster_id=""

# Find cluster
clusters=$(ai_get_clusters)
clusters_len=$(echo "${clusters}" | jq length)
for i in  $(seq 1 $clusters_len); do
  cn=$(echo "${clusters}" | jq -r ".[$((i-1))].name")
  if [[ "$cn" == "$KUBERNETES_CLUSTER_NAME" ]]; then
    echo "INFO: We have found cluster $cn"
    cluster_id=$(echo "${clusters}" | jq -r ".[$((i-1))].id")
  else
    echo "INFO: skip cluster $cn"
  fi
done

echo "INFO: cluster id $cluster_id"
if [ -z "$cluster_id" ] ; then 
  echo "INFO: Create new cluster $KUBERNETES_CLUSTER_NAME"
  cluster_id=$(ai_post_cluster)
fi

if [[ -z ${cluster_id} ]]; then
  echo "ERROR: unable to find cluster"
  exit 1
fi

# Upload tf-openshift manifests to assisted installer
echo "INFO: post manifests"
ai_post_manifests $cluster_id

# Update Install Config for Contrail SDN
echo "INFO: update config to set TF SDN"
ai_update_install_config $cluster_id

# V2: create infra-env for cluster
infra_id=$(ai_create_infra_env $cluster_id)

# Generate and download ISO from assisted installer
echo "INFO: download iso for infra env id $infra_id"
ai_download_iso $infra_id ${LIBVIRT_DIR}/ai_install_ocp_image.iso

machine_names=""

# Run machines
for i in $(seq 1 ${controller_count}); do
    echo "INFO: start master-$i vm"
    start_openshift_vm ${KUBERNETES_CLUSTER_NAME}-master-${i} ${MASTER_MEM} ${MASTER_CPU} master "52:54:00:13:31:0${i}" "${LIBVIRT_DIR}/ai_install_ocp_image.iso"
    machine_names+=" ${KUBERNETES_CLUSTER_NAME}-master-${i}"
done

for i in $(seq 1 ${agent_count}); do
    echo "INFO: start worker-$i vm"
    start_openshift_vm ${KUBERNETES_CLUSTER_NAME}-worker-${i} ${WORKER_MEM} ${WORKER_CPU} worker "52:54:00:13:41:0${i}" "${LIBVIRT_DIR}/ai_install_ocp_image.iso"
    machine_names+=" ${KUBERNETES_CLUSTER_NAME}-worker-${i}"
done

echo "INFO: start VM power monitor $(date)"
ai_monitor_vms $machine_names 2>/dev/null &
mpid=$!

function _stop_monitor() {
    local mpid=$1
    echo "INFO: stop VM power monitor: pid=$mpid"
    kill $mpid
    wait $mpid || true
    echo "INFO: VM power monitor stopped"
}

# wait machines
for i in $machine_names ; do
    mip=$(get_ip_mac $i | awk '{print $1}')
    if [ -z "$mip" ] ; then
        _stop_monitor $mpid
        echo "ERROR: failed to get IP for $i"
        exit 1
    fi
    wait_ssh core@${mip}
done

echo "INFO: wait for hosts status 'known' ($(date))"
wait_cmd_success "ai_check_hosts_status_ready ${infra_id}" 10 60

# Start cluster installation
echo "INFO: start install $(date)"
ai_start_cluster ${cluster_id}

# Wait installation completed
echo "INFO: wait for install completed or finalizing started"
err_statuses='cancelled error'
wait_cmd_success "ai_check_cluster_status ${cluster_id} $err_statuses installed finalizing" 10 360

_stop_monitor $mpid

# Download kubeconfig locally
echo "INFO: download kubeconfig"
mkdir -p $(dirname $KUBECONFIG)
ai_get_kubeconfig ${cluster_id} | tee $KUBECONFIG

# Wait installation completed
echo "INFO: wait for install completed"
wait_cmd_success "ai_check_cluster_status ${cluster_id} $err_statuses installed" 10 360

echo "INFO: installation completed"
