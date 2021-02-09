#!/bin/bash -x

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
[ ! -e "$TF_STACK_PROFILE" ] || source "$TF_STACK_PROFILE"

export OPERATOR_REPO=${OPERATOR_REPO:-$WORKSPACE/tf-operator}

kubectl delete -k $OPERATOR_REPO/deploy/kustomize/operator/templates/ || true
kubectl delete -k $OPERATOR_REPO/deploy/kustomize/contrail/templates/ || true
kubectl delete -f $OPERATOR_REPO/deploy/crds/ || true

c=0
for i in $CONTROLLER_NODES ; do
  kubectl delete pv  cassandra1-pv-$c zookeeper1-pv-$c || true
  c=$(( c + 1))
  ssh $SSH_OPTIONS $SSH_USER@$i \
    sudo rm -rf \
      /mnt/cassandra \
      /mnt/zookeeper \
      /var/lib/contrail \
      /var/log/contrail \
      /var/crashes/contrail \
      /etc/cni/net.d/10-tf-cni.conf || true
done

for i in $AGENT_NODES ; do
  ssh $SSH_OPTIONS $SSH_USER@$i \
    sudo rm -rf \
      /var/lib/contrail \
      /var/log/contrail \
      /var/crashes/contrail \
      /etc/cni/net.d/10-tf-cni.conf || true
done
