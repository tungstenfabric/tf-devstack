#!/bin/bash -xe
TF_HELM_URL=${TF_HELM_URL:-https://github.com/tungstenfabric/tf-helm-deployer/archive/master.tar.gz}
wget $TF_HELM_URL -O contrail-helm-deployer.tar.gz
mkdir -p contrail-helm-deployer
tar xzf contrail-helm-deployer.tar.gz --strip-components=1 -C contrail-helm-deployer

cd contrail-helm-deployer

pgrep -f "helm serve" | xargs -n1 -r kill
helm serve &
sleep 5
make all

# Refactor for AGENT_NODES and CONTROLLER_NODES
# Mark controller after vrouter installed
for node in $(kubectl get nodes --no-headers | cut -d' ' -f1); do
  kubectl label node --overwrite $node opencontrail.org/controller-
  kubectl label node --overwrite $node opencontrail.org/vrouter-kernel=enabled
done

if [ -z "$AGENT_NODES" ]; then
  echo "AGENT_NODES must be set"
fi

if [ -z "$CONTROLLER_NODES" ]; then
  echo "CONTROLLER_NODES must be set"
fi

NODES_ARGS="--set global.contrail_env.CONTROLLER_NODES=$CONTROLLER_NODES"
JVM_ARGS="--set global.contrail_env.JVM_EXTRA_OPTS='-Xms1g -Xmx2g'"

# Create /var/log/contrail dir because it's not created in centos automatically by k8s
# but is mounted to containers
mkdir -p /var/log/contrail

kubectl create ns tungsten-fabric || :
helm upgrade --install --namespace tungsten-fabric tungsten-fabric contrail $NODES_ARGS $JVM_ARGS
echo "Waiting for vrouter to be ready"
kubectl wait --for=condition=Ready --timeout=420s -l component=contrail-vrouter-agent-kernel

for node in $(kubectl get nodes --no-headers | cut -d' ' -f1); do
  kubectl label node --overwrite $node opencontrail.org/controller=enabled
done
