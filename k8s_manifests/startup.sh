#!/bin/bash

set -o errexit

# constants

deployer_image=contrail-k8s-manifests
deployer_name=contrail-container-buider
deployer_dir=contrail-container-builder

# default env variables

DEV_ENV=${DEV_ENV:-false}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-opencontrailnightly}
CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-master-latest}
SKIP_K8S_DEPLOYMENT=${SKIP_K8S_DEPLOYMENT:-false}
SKIP_CONTRAIL_DEPLOYMENT=${SKIP_CONTRAIL_DEPLOYMENT:-false}
SKIP_MANIFEST_CREATION=${SKIP_MANIFEST_CREATION:-false}
KUBE_MANIFEST=${KUBE_MANIFEST:-$deployer_dir/kubernetes/manifests/contrail-standalone-kubernetes.yaml}

[ "$(whoami)" == "root" ] && echo Please run script as non-root user && exit

if [ $SKIP_K8S_DEPLOYMENT == false ]; then
    distro=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
    echo $distro detected.

    # install required packages

    if [ "$distro" == "centos" ]; then
        sudo yum install -y python3 python3-pip libyaml-devel python3-devel ansible git
    elif [ "$distro" == "ubuntu" ]; then
        apt-get update
        apt-get install -y python3 python3-pip libyaml-devel python3-devel ansible git
    else
        echo "Unsupported OS version" && exit
    fi

    PHYSICAL_INTERFACE=`ip route get 1 | grep -o 'dev.*' | awk '{print($2)}'`
    NODE_IP=`ip addr show dev $PHYSICAL_INTERFACE | grep 'inet ' | awk '{print $2}' | head -n 1 | cut -d '/' -f 1`

    # show config variables

    [ "$NODE_IP" != "" ] && echo "Node IP: $NODE_IP"
    echo "Build from source: $DEV_ENV" # true or false
    echo "Orchestrator: $ORCHESTRATOR" # kubernetes or openstack
    [ "$ORCHESTRATOR" == "openstack" ] && echo "OpenStack version: $OPENSTACK_VERSION"
    echo

    # prepare ssh key authorization

    [ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
    [ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
    [ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
    grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

    # deploy kubespray

    [ ! -d kubespray ] && git clone https://github.com/kubernetes-sigs/kubespray.git
    cd kubespray/
    sudo pip3 install -r requirements.txt

    cp -rfp inventory/sample/ inventory/mycluster
    declare -a IPS=( $NODE_IP )
    CONFIG_FILE=inventory/mycluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
    sed -i 's/calico/cni/g' inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml

    ansible-playbook -i inventory/mycluster/hosts.yml --become --become-user=root cluster.yml

    mkdir -p ~/.kube
    sudo cp /root/.kube/config ~/.kube/config
    sudo chown -R $(id -u):$(id -g) ~/.kube

    cd ../
fi

# build step

if [ $DEV_ENV == true ]; then
    # get tf-dev-env
    [ -d /root/tf-dev-env ] && rm -rf /root/tf-dev-env
    cd /root && git clone https://github.com/tungstenfabric/tf-dev-env.git

    # build all
    cd /root/tf-dev-env && AUTOBUILD=1 BUILD_DEV_ENV=1 ./startup.sh

    # fix env variables
    CONTAINER_REGISTRY="$(docker inspect --format '{{(index .IPAM.Config 0).Gateway}}' bridge):6666"
    CONTRAIL_CONTAINER_TAG="dev"
    git clone https://github.com/Juniper/$deployer_name.git "$base_deployers_dir"
elif [ $SKIP_MANIFEST_CREATION == false ]; then
    echo "Creating manifest"
    sudo rm -rf $deployer_dir
    sudo docker run --name $deployer_image -d --rm --entrypoint "/usr/bin/tail" $CONTAINER_REGISTRY/$deployer_image:$CONTRAIL_CONTAINER_TAG -f /dev/null
    sudo docker cp $deployer_image:$deployer_dir .
    sudo docker stop $deployer_image
    export CONTRAIL_REGISTRY=$CONTAINER_REGISTRY
    export CONTRAIL_VERSION=$CONTRAIL_CONTAINER_TAG
    export HOST_IP=$NODE_IP
    export PHYSICAL_INTERFACE=$PHYSICAL_INTERFACE
    export JVM_EXTRA_OPTS="-Xms1g -Xmx2g"
    $deployer_dir/kubernetes/manifests/resolve-manifest.sh $KUBE_MANIFEST > contrail.yaml
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
fi

# show results

echo "Deployment scripts are finished"
echo "Now you can monitor when contrail becomes available with:"
echo "kubectl get pods --all-namespaces"
echo "All services should become Running before you can use Contrail"
echo "If agent is in Error state you might need to upgrade your kernel with 'sudo yum update -y' and reboot the node"
echo "If agent is in a permanent CrashLoopBackOff state and other Contrail containers are Running, please reboot the node"
echo "Contrail Web UI will be available at https://$NODE_IP:8143"
