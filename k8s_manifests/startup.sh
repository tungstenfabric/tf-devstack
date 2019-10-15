#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

# default env variables

DEV_ENV=${DEV_ENV:-false}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-opencontrailnightly}
CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-master-latest}
SKIP_K8S_DEPLOYMENT=${SKIP_K8S_DEPLOYMENT:-false}
SKIP_CONTRAIL_DEPLOYMENT=${SKIP_CONTRAIL_DEPLOYMENT:-false}
SKIP_MANIFEST_CREATION=${SKIP_MANIFEST_CREATION:-false}
KUBE_MANIFEST=${KUBE_MANIFEST:-$deployer_dir/kubernetes/manifests/contrail-standalone-kubernetes.yaml}
CONTROLLER_NODES=${CONTROLLER_NODES:-$NODE_IP}
AGENT_NODES=${AGENT_NODES:-$NODE_IP}
CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

# constants

AGENT_LABEL="node-role.opencontrail.org/agent="

if [ $SKIP_K8S_DEPLOYMENT == false ]; then
    export K8S_NODES=$AGENT_NODES
    export K8S_MASTERS=$CONTROLLER_NODES
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
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
    export JVM_EXTRA_OPTS="-Xms1g -Xmx2g"
    $my_dir/../common/fetch_deployer.sh
    $DEPLOYER_DIR/kubernetes/manifests/resolve-manifest.sh $KUBE_MANIFEST > contrail.yaml
    echo "Manifest contrail.yaml is created"
fi

# deploy Contrail

if [ $SKIP_CONTRAIL_DEPLOYMENT == false ]; then

    # label nodes

    nodes=( `kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'` )
    labels=( $(grep "key: \"node-role." contrail.yaml | tr -s [:space:] | sort -u | cut -d: -f2 | tr -d \") )
    echo Labelling nodes: ${nodes[*]} Agents: $AGENT_NODES Controllers: $CONTROLLER_NODES
    for i in $(seq 1 ${#nodes[@]})
    do
        existing_labels=`kubectl get nodes node$i --show-labels`
        if [[ $CONTROLLER_NODES == *${nodes[i-1]}* ]]; then
            # [[ `kubectl taint node node1 node.kubernetes.io/master=true:NoSchedule` ]] || true
            for label in ${labels[@]}
            do
                if [[ $existing_labels != *"$label="* ]]; then
                    echo Label node$i with $label=
                    kubectl label nodes node$i $label=
                fi
            done
        else
            # [[ `kubectl taint node node1 node.kubernetes.io/master-` ]] || true
            if [[ $existing_labels != *$AGENT_LABEL* ]]; then
                echo Label node$i with $AGENT_LABEL
                kubectl label nodes node$i $AGENT_LABEL
            fi
        fi
    done

    # apply manifests

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
