#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/definitions

# Remove bootstrap node
sudo virsh destroy ${KUBERNETES_CLUSTER_NAME}-bootstrap > /dev/null || err "virsh destroy ${KUBERNETES_CLUSTER_NAME}-bootstrap failed"
sudo virsh undefine ${KUBERNETES_CLUSTER_NAME}-bootstrap --remove-all-storage > /dev/null || err "virsh undefine ${KUBERNETES_CLUSTER_NAME}-bootstrap --remove-all-storage"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}" \
    "sed -i '/bootstrap\.${KUBERNETES_CLUSTER_NAME}\.${KUBERNETES_CLUSTER_DOMAIN}/d' /etc/haproxy/haproxy.cfg" || err "failed"
ssh -i ${OPENSHIFT_SSH_KEY} $SSH_OPTS "${LB_SSH_USER}@lb.${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}" "systemctl restart haproxy" || err "failed"
