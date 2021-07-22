#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-'master'}
if [[ "$OPENSHIFT_VERSION" == 'master' ]]; then
    export OPENSHIFT_VERSION='4.6'
fi

source $my_dir/definitions

for i in $(seq 1 5); do
    sudo virsh destroy ${KUBERNETES_CLUSTER_NAME}-worker-${i} || /bin/true
    sudo virsh undefine ${KUBERNETES_CLUSTER_NAME}-worker-${i} --remove-all-storage || /bin/true
done
for i in $(seq 1 5); do
    sudo virsh destroy ${KUBERNETES_CLUSTER_NAME}-master-${i} || /bin/true
    sudo virsh undefine ${KUBERNETES_CLUSTER_NAME}-master-${i} --remove-all-storage || /bin/true
done

sudo virsh destroy ${KUBERNETES_CLUSTER_NAME}-bootstrap || /bin/true
sudo virsh undefine ${KUBERNETES_CLUSTER_NAME}-bootstrap --remove-all-storage || /bin/true
sudo virsh destroy ${KUBERNETES_CLUSTER_NAME}-lb || /bin/true
sudo virsh undefine ${KUBERNETES_CLUSTER_NAME}-lb --remove-all-storage || /bin/true

for i in ${VIRTUAL_NET//,/ } ; do
    sudo virsh net-destroy $i || /bin/true
    sudo virsh net-undefine $i || /bin/true
done
