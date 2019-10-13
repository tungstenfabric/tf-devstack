#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

# constants

DEPLOYER_IMAGE=contrail-k8s-manifests
DEPLOYER_NAME=contrail-container-buider
DEPLOYER_DIR=contrail-container-builder

# default env variables

DEV_ENV=${DEV_ENV:-false}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-opencontrailnightly}
CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-master-latest}
SKIP_K8S_DEPLOYMENT=${SKIP_K8S_DEPLOYMENT:-false}
SKIP_CONTRAIL_DEPLOYMENT=${SKIP_CONTRAIL_DEPLOYMENT:-false}
SKIP_MANIFEST_CREATION=${SKIP_MANIFEST_CREATION:-false}
KUBE_MANIFEST=${KUBE_MANIFEST:-$deployer_dir/kubernetes/manifests/contrail-standalone-kubernetes.yaml}

if [ $SKIP_K8S_DEPLOYMENT == false ]; then
    $my_dir/../common/deploy_kubespray.sh
fi

# build step

if [ $DEV_ENV == true ]; then
    "$my_dir/../common/dev_env.sh"
elif [ $SKIP_MANIFEST_CREATION == false ]; then
    echo "Creating manifest"
    export CONTRAIL_REGISTRY=$CONTAINER_REGISTRY
    export CONTRAIL_VERSION=$CONTRAIL_CONTAINER_TAG
    export HOST_IP=$NODE_IP
    export PHYSICAL_INTERFACE=$PHYSICAL_INTERFACE
    export JVM_EXTRA_OPTS="-Xms1g -Xmx2g"
    $my_dir/../common/fetch_deployer.sh
    $DEPLOYER_DIR/kubernetes/manifests/resolve-manifest.sh $KUBE_MANIFEST > contrail.yaml
    echo "Manifest contrail.yaml is created"
fi

# deploy Contrail

if [ $SKIP_CONTRAIL_DEPLOYMENT == false ]; then
    labels=( $(grep "key: \"node-role." contrail.yaml | tr -s [:space:] | sort -u | cut -d: -f2 | tr -d \") )
    existing_labels=`kubectl get nodes --show-labels`
    for label in ${labels[@]}
    do
        if [[ $existing_labels != *"$label="* ]]; then
            kubectl label nodes node1 $label=
        fi
    done
    kubectl apply -f contrail.yaml

    # show results

    echo "Deployment scripts are finished"
    echo "Now you can monitor when contrail becomes available with:"
    echo "kubectl get pods --all-namespaces"
    echo "All pods should become Running before you can use Contrail"
    echo "If agent is in Error state you might need to upgrade your kernel with 'sudo yum update -y' and reboot the node"
    echo "If agent is in a permanent CrashLoopBackOff state and other Contrail containers are Running, please reboot the node"
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
fi
