#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"
source "$my_dir/functions.sh"

# parameters

K8S_MASTERS=${K8S_MASTERS:-$NODE_IP}
K8S_NODES=${K8S_NODES:-$NODE_IP}
K8S_POD_SUBNET=${K8S_POD_SUBNET:-}
K8S_SERVICE_SUBNET=${K8S_SERVICE_SUBNET:-}
CNI=${CNI:-cni}
# kubespray parameters like CLOUD_PROVIDER can be set as well prior to calling this script

[ "$(whoami)" == "root" ] && echo Please run script as non-root user && exit 1

# install required packages

if [ "$DISTRO" == "centos" ]; then
    sudo yum install -y python3 python3-pip libyaml-devel python3-devel git
elif [ "$DISTRO" == "ubuntu" ]; then
    #TODO: should be broken for now
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip libyaml-dev python3-dev git

    ubuntu_release=`lsb_release -r | awk '{split($2,a,"."); print a[1]}'`
    if [ 16 -eq $ubuntu_release ]; then
        sudo apt-add-repository --yes --update ppa:ansible/ansible-2.7
        sudo apt update
        sudo apt install -y ansible python3-cffi python3-crypto libssl-dev
        pip3 install pyOpenSSL
    fi

else
    echo "Unsupported OS version" && exit 1
fi

# prepare ssh key authorization for all-in-one single node deployment

set_ssh_keys

# setup timeserver

setup_timeserver

# deploy kubespray

[ ! -d kubespray ] && git clone --depth 1 --single-branch https://github.com/kubernetes-sigs/kubespray.git
cd kubespray/
sudo pip3 install -r requirements.txt

cp -rfp inventory/sample/ inventory/mycluster
declare -a IPS=( $K8S_MASTERS $K8S_NODES )
masters=( $K8S_MASTERS )
echo Deploying to IPs ${IPS[@]} with masters ${masters[@]}
export KUBE_MASTERS_MASTERS=${#masters[@]}
CONFIG_FILE=inventory/mycluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
sed -i "s/kube_network_plugin: .*/kube_network_plugin: $CNI/g" inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml

echo "helm_enabled: true" >> inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml

# DNS
# Allow host and hostnet pods to resolve cluster domains
echo "resolvconf_mode: host_resolvconf" >> inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml
echo "enable_nodelocaldns: false" >> inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml

# Grab first nameserver from /etc/resolv.conf that is not coredns
if sudo systemctl is-enabled systemd-resolved.service; then
  nameserver=$(grep -i nameserver /run/systemd/resolve/resolv.conf | grep -v $(echo $K8S_SERVICE_SUBNET | cut -d. -f1-2) | head -1 | awk '{print $2}')
  resolvfile=/run/systemd/resolve/resolv.conf
else
  nameserver=$(grep -i nameserver /etc/resolv.conf | grep -v $(echo $K8S_SERVICE_SUBNET | cut -d. -f1-2) | head -1 | awk '{print $2}')
  resolvfile=/etc/resolv.conf
fi
if [ -z "$nameserver" ]; then
  echo "FATAL: No existing nameservers detected. Please set one in $resolvfile before deploying again."
  exit 1
fi
# Set upstream DNS server used by host and coredns for recursive lookups
echo "upstream_dns_servers: ['$nameserver']" >> inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml
echo "nameservers: ['$nameserver']" >> inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml
# Fix coredns deployment on single node
echo "dns_min_replicas: 1" >> inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml
# enable docker live restore option
echo "docker_options: '--live-restore'" >> inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml

extra_vars=""
[[ -n $K8S_POD_SUBNET ]] && extra_vars="-e kube_pods_subnet=$K8S_POD_SUBNET"
[[ -n $K8S_SERVICE_SUBNET ]] && extra_vars="$extra_vars -e kube_service_addresses=$K8S_SERVICE_SUBNET"
ansible-playbook -i inventory/mycluster/hosts.yml --become --become-user=root cluster.yml $extra_vars "$@"

mkdir -p ~/.kube
sudo cp /root/.kube/config ~/.kube/config
sudo chown -R $(id -u):$(id -g) ~/.kube

cd ../
