#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

# default env variables

WORKSPACE="$(pwd)"
DEPLOYER_IMAGE="contrail-helm-deployer"
DEPLOYER_DIR="root"

SKIP_K8S_DEPLOYMENT=${SKIP_K8S_DEPLOYMENT:-false}
SKIP_OPENSTACK_DEPLOYMENT=${SKIP_OPENSTACK_DEPLOYMENT:-false}
SKIP_CONTRAIL_DEPLOYMENT=${SKIP_CONTRAIL_DEPLOYMENT:-false}
CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}
ORCHESTRATOR=${ORCHESTRATOR:-"openstack"}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-queens}

if [[ "$ORCHESTRATOR" == "kubernetes" ]]; then
  export $SKIP_OPENSTACK_DEPLOYMENT=true
elif [[ "$ORCHESTRATOR" == "openstack" ]]; then
  export CNI=${CNI:-calico}
else
  echo "Set ORCHESTRATOR environment variable with value \"kubernetes\" or \"openstack\"  "
  exit
fi


# build step

if [[ "$DEV_ENV" == true ]]; then
    "$my_dir/../common/dev_env.sh"
fi

# kubernetes

if [[ "$SKIP_K8S_DEPLOYMENT" == false ]]; then
    export K8S_NODES=$AGENT_NODES
    export K8S_MASTERS=$CONTROLLER_NODES
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
    $my_dir/../common/deploy_kubespray.sh
fi

#fetch_deployer

# deploy helm-openstack

if [[ "$SKIP_OPENSTACK_DEPLOYMENT" == false ]]; then
    $my_dir/../common/deploy_helm_openstack.sh
fi

# Late labelling for controller pods to be deployed

# deploy Tungsten Fabric

if [[ "$SKIP_CONTRAIL_DEPLOYMENT" == false ]]; then
    $my_dir/deploy_tf_helm.sh
    wait_nic_up vhost0
    label_nodes_by_ip opencontrail.org/controller=enabled $CONTROLLER_NODES
fi

# show results

echo "Deployment scripts are finished"
echo "Now you can monitor when contrail becomes available with:"
echo "kubectl get pods --all-namespaces"
echo "All pods should become Running before you can use Contrail"
echo "If agent is in Error state you might need to upgrade your kernel with 'sudo yum update -y' on agent node and reboot the node"
echo "If agent is in a permanent CrashLoopBackOff state and other Contrail containers are Running, please reboot the node"
echo "Contrail Web UI will be available at any IP(or name) from '$CONTROLLER_NODES': https://IP:8143"
