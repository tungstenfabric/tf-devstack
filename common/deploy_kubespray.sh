#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"

[ "$(whoami)" == "root" ] && echo Please run script as non-root user && exit

# install required packages

if [ "$distro" == "centos" ]; then
    sudo yum install -y python3 python3-pip libyaml-devel python3-devel ansible git
elif [ "$distro" == "ubuntu" ]; then
    #TODO: should be broken for now
    apt-get update
    apt-get install -y python3 python3-pip libyaml-devel python3-devel ansible git
else
    echo "Unsupported OS version" && exit
fi

# prepare ssh key authorization for all-in-one single node deployment

[ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
[ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
[ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# deploy kubespray

[ ! -d kubespray ] && git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray/
sudo pip3 install -r requirements.txt

cp -rfp inventory/sample/ inventory/mycluster
declare -a IPS=( $CONTROLLER_NODES $AGENT_NODES )
CONFIG_FILE=inventory/mycluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
sed -i 's/calico/cni/g' inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml

ansible-playbook -i inventory/mycluster/hosts.yml --become --become-user=root cluster.yml

mkdir -p ~/.kube
sudo cp /root/.kube/config ~/.kube/config
sudo chown -R $(id -u):$(id -g) ~/.kube

cd ../
