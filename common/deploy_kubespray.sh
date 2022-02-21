#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"
source "$my_dir/functions.sh"
source "$my_dir/workaround.sh"

function is_kubeapi_accessible() {
  local x
  2>/dev/null exec {x}</dev/tcp/$1/6443 || return 1
  exec {x}<&-
  return 0
}

function set_env_var() {
  local name="$1"
  local val="$2"
  local file="$3"
  local sep=${4:-'/'}
  if grep -q "^${name}:" $file ; then
    sed -i "s${sep}^${name}:.*${sep}${name}: $val${sep}g" $file
  else
    echo "${name}: ${val}" >> $file
  fi
}

# parameters

KUBESPRAY_TAG=${KUBESPRAY_TAG:="release-2.16"}
K8S_MASTERS=${K8S_MASTERS:-$NODE_IP}
K8S_NODES=${K8S_NODES:-$NODE_IP}
K8S_POD_SUBNET=${K8S_POD_SUBNET:-"10.32.0.0/12"}
K8S_SERVICE_SUBNET=${K8S_SERVICE_SUBNET:-"10.96.0.0/12"}
K8S_VERSION=${K8S_VERSION:-"v1.21.1"}
K8S_CLUSTER_NAME=${K8S_CLUSTER_NAME:-''}
K8S_DOMAIN=${K8S_DOMAIN:-''}

# 'docker' is a default engine for CONTAINER_RUNTIME. 'containerd' is supported (with runc by default)
CNI=${CNI:-cni}
IGNORE_APT_UPDATES_REPO=${IGNORE_APT_UPDATES_REPO:-false}
LOOKUP_NODE_HOSTNAMES=${LOOKUP_NODE_HOSTNAMES:-true}
CRYPTOGRAPHY_ALLOW_OPENSSL_102=true

# Apply docker cli workaround
k8s_major=$(echo $K8S_VERSION | cut -d '.' -f 2)
if (( k8s_major <= 16 )); then
  workaround_kubespray_docker_cli
fi

# kubespray parameters like CLOUD_PROVIDER can be set as well prior to calling this script

[ "$(whoami)" == "root" ] && echo "ERROR: Please run script as non-root user" && exit 1

# install required packages

if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
    sudo yum install -y python3 python3-pip libyaml-devel python3-devel git
elif [ "$DISTRO" == "ubuntu" ]; then
    # Ensure updates repo is available
    if [[ "$IGNORE_APT_UPDATES_REPO" != "false" ]] && ! apt-cache policy | grep http | awk '{print $2 $3}' | sort -u | grep -q updates; then
        echo "ERROR: Ubuntu updates repo could not be found! Please check your apt sources" 1>&2
        echo "ERROR: If you believe this to be a mistake and want to proceed, set IGNORE_APT_UPDATES_REPO=true and run again." 1>&2
        exit 1
    fi
    export DEBIAN_FRONTEND=noninteractive
    sudo -E apt-get update -y
    sudo -E apt-get -y purge unattended-upgrades || /bin/true
    sudo -E apt-get install -y python3 python3-pip libyaml-dev python3-dev git

    ubuntu_release=`lsb_release -r | awk '{split($2,a,"."); print a[1]}'`
    if [ 16 -eq $ubuntu_release ]; then
        sudo apt-add-repository --yes --update ppa:ansible/ansible-2.7
        sudo apt update
        sudo apt install -y ansible python3-cffi python3-crypto libssl-dev
        pip3 install pyOpenSSL
    fi
else
    echo "ERROR: Unsupported OS version" && exit 1
fi
sudo python3 -m pip install --upgrade pip==21.1.3

# prepare ssh key authorization for all-in-one single node deployment

set_ssh_keys

# setup timeserver

setup_timeserver

# deploy kubespray

[ ! -d kubespray ] && git clone --depth 1 --single-branch --branch=${KUBESPRAY_TAG} https://github.com/kubernetes-sigs/kubespray.git
cd kubespray/

# If we now install the cryptography and cffi of the required version, then the newest versions will not be installed together with the ansible
#sudo pip3 install -c${UPPER_CONSTRAINTS_FILE:=https://releases.openstack.org/constraints/upper/${OPENSTACK_VERSION:-master}} cryptography cffi

sudo pip3 install -r requirements.txt

cp -rfp inventory/sample/ inventory/mycluster
cluster_vars="inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml"
if [ ! -e $cluster_vars ]; then
  # releases < 2.16 has different naming
  cluster_vars="inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml"
fi
declare -a IPS=( $K8S_MASTERS $K8S_NODES )
masters=( $K8S_MASTERS )

# Copy devstack-directory to another nodes
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
devstack_dir="$(basename $(dirname $my_dir))"
for machine in $(echo "$CONTROLLER_NODES $AGENT_NODES" | tr " " "\n" | sort -u); do
  if ! ip a | grep -q "$machine"; then
    echo "INFO: Copy devstack from master to $machine"
    scp -r $ssh_opts $(dirname $my_dir) $machine:/tmp/
  fi
  if [[ -n "$HUGE_PAGES_2MB" ]]; then
    ssh $ssh_opts $machine "echo 'vm.nr_hugepages = $HUGE_PAGES_2MB' | sudo tee /etc/sysctl.d/tf-hugepages.conf"
    ssh $ssh_opts $machine "sudo sysctl --system"
  fi
done

echo "INFO: Deploying to IPs ${IPS[@]} with masters ${masters[@]}"
export KUBE_MASTERS_MASTERS=${#masters[@]}
export KUBE_CONTROL_HOSTS=${#masters[@]}
if ! [ -e inventory/mycluster/hosts.yml ] && [[ "$LOOKUP_NODE_HOSTNAMES" == "true" ]]; then
  echo "INFO: lookup node hostnames and ips"
  node_count=0
  declare -a hnames
  for ip in $(echo ${IPS[@]} | tr ' ' '\n' | awk '!x[$0]++'); do
    declare -A IPS_WITH_HOSTNAMES
    hostname=$(ssh $ssh_opts $ip hostname -f)
    ip_=$ip
    if [ -n "$MANAGEMENT_NETWORK" ] ; then
      ip_=$(ssh $ssh_opts $ip /sbin/ip route get $MANAGEMENT_NETWORK | grep -o "src .*" | cut -d ' ' -f 2)
      if [ -z "$ip_" ] ; then
        echo "ERROR: failed to detect ip by management network cidr $MANAGEMENT_NETWORK"
        exit 1
      fi
    fi
    IPS_WITH_HOSTNAMES[$hostname]=$ip_
    hnames=( ${hnames[@]} $hostname )
    ((node_count+=1))
  done
  inventory_data=$(for host in "${hnames[@]}"; do echo -n "$host,${IPS_WITH_HOSTNAMES[$host]} "; done)
  # Test if all hostnames were unique
  if [[ "${#IPS_WITH_HOSTNAMES[@]}" != "$node_count" ]]; then
    echo "ERROR: Not all hosts have unique hostnames." 1>&2
    echo "To use automatic host naming, set LOOKUP_NODE_HOSTNAMES=false" 1>&2
    exit 1
  fi
  echo "INFO: inventory data: $inventory_data"
  CONFIG_FILE=inventory/mycluster/hosts.yml python3 contrib/inventory_builder/inventory.py $inventory_data
else
  echo "INFO: inventory data: ${IPS[@]}"
  CONFIG_FILE=inventory/mycluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
fi
echo "INFO: inventory/mycluster/hosts.yml"
cat inventory/mycluster/hosts.yml

set_env_var "kube_network_plugin" "$CNI" $cluster_vars

if [[ "${ORCHESTRATOR}" == "helm" ]]; then
  set_env_var 'helm_enabled' true $cluster_vars
  # TODO: use different version for kubespray release != 2.14
  set_env_var 'helm_version' 'v2.16.11' $cluster_vars
  set_env_var 'helm_stable_repo_url' 'https://charts.helm.sh/stable' $cluster_vars '|'
fi

# DNS
# Allow host and hostnet pods to resolve cluster domains
set_env_var 'resolvconf_mode' 'host_resolvconf' $cluster_vars
set_env_var 'enable_nodelocaldns' 'false' $cluster_vars

# Grab first nameserver from /etc/resolv.conf that is not coredns
if sudo systemctl is-enabled systemd-resolved.service; then
  nameserver=$(grep -i nameserver /run/systemd/resolve/resolv.conf | grep -v $(echo $K8S_SERVICE_SUBNET | cut -d. -f1-2) | head -1 | awk '{print $2}')
  resolvfile=/run/systemd/resolve/resolv.conf
else
  nameserver=$(grep -i nameserver /etc/resolv.conf | grep -v $(echo $K8S_SERVICE_SUBNET | cut -d. -f1-2) | awk '{print $2}' | sed "s/^\(.*\)$/'\1'/" | tr '\n' ',' | sed 's/,$//' )
  resolvfile=/etc/resolv.conf
fi
if [ -z "$nameserver" ]; then
  echo "ERROR: No existing nameservers detected. Please set one in $resolvfile before deploying again."
  exit 1
fi
# Set upstream DNS server used by host and coredns for recursive lookups
set_env_var 'upstream_dns_servers' "[$nameserver]" $cluster_vars
set_env_var 'nameservers' "[$nameserver]" $cluster_vars
# Fix coredns deployment on single node
set_env_var 'dns_min_replicas' '1' $cluster_vars

# Set explicetely k8s cluster name (some orchestrators like operator use name from kubernetes
# and tf-test use hardcoded 'k8s' cluster name)
if [[ -n "${K8S_CLUSTER_NAME}" ]]; then
  set_env_var 'cluster_name' "$K8S_CLUSTER_NAME" $cluster_vars
fi

# K8S_DOMAIN
if [ -n "$K8S_DOMAIN" ] ; then
  set_env_var 'dns_domain' "$K8S_DOMAIN" $cluster_vars
fi

if [[ -n "$CONTAINER_RUNTIME" ]] ; then
  set_env_var 'container_manager' "$CONTAINER_RUNTIME" $cluster_vars
  if [[ "$CONTAINER_RUNTIME" == 'crio' ]] ; then
    set_env_var 'crio_pids_limit' 8192 $cluster_vars
  fi
  if [[ "$CONTAINER_RUNTIME" != 'docker' ]]; then
    set_env_var 'etcd_deployment_type' 'host' $cluster_vars
  fi
fi

# Set local docker registries if defined
if [[ -n "${DOCKER_CACHE_REGISTRY}" ]]; then
  set_env_var 'quay_image_repo' "$DOCKER_CACHE_REGISTRY" $cluster_vars '|'
  set_env_var 'kube_image_repo' "$DOCKER_CACHE_REGISTRY" $cluster_vars '|'
  set_env_var 'gcr_image_repo' "$DOCKER_CACHE_REGISTRY" $cluster_vars '|'
  set_env_var 'docker_image_repo' "$DOCKER_CACHE_REGISTRY" $cluster_vars '|'
fi

if [[ -z "$CONTAINER_RUNTIME" || "$CONTAINER_RUNTIME" == 'docker' ]]; then
  # enable docker live restore option
  #
  # set live-restore via config file to avoid conflicts between command line and
  # config file parametrs (docker fails to start if a parameter is in both places).
  # tf-dev-env and deployment methods (not using kubespray) use config file approach.
  #    the way via kubespray:
  #    echo "docker_options: '--live-restore'" >> $cluster_vars
  echo "INFO: Create /etc/docker/daemon.json on all nodes"
  # Master-node
  sudo -E $my_dir/create_docker_config.sh
  # All another nodes
  for machine in $(echo "$CONTROLLER_NODES $AGENT_NODES" | tr " " "\n" | sort -u); do
    if ! ip a | grep -q "$machine"; then
      ssh $ssh_opts $machine "sudo yum install -y python3 python3-pip"
      ssh $ssh_opts $machine "export CONTAINER_REGISTRY=$CONTAINER_REGISTRY ; export DEPLOYER_CONTAINER_REGISTRY=$DEPLOYER_CONTAINER_REGISTRY ; sudo -E /tmp/${devstack_dir}/common/create_docker_config.sh"
    fi
  done
fi

extra_vars=""
[[ -n $K8S_POD_SUBNET ]] && extra_vars="-e kube_pods_subnet=$K8S_POD_SUBNET"
[[ -n $K8S_SERVICE_SUBNET ]] && extra_vars="$extra_vars -e kube_service_addresses=$K8S_SERVICE_SUBNET"
[[ -n $K8S_VERSION ]] && extra_vars="$extra_vars -e kube_version=$K8S_VERSION"
ansible-playbook -i inventory/mycluster/hosts.yml --become --become-user=root cluster.yml $extra_vars "$@"

mkdir -p ~/.kube
sudo cp /root/.kube/config ~/.kube/config
sudo chown -R $(id -u):$(id -g) ~/.kube

# NB. kubespray deletes k8s_POD_kube-apiserver ct in the end to
# trigger a kube-apiserver reset thus kube API can be available
# for a moment and then disappears. the port test is not enough
# let's wait for k8s_POD_kube-apiserver cts first to catch the
# kube-apiserver POD restart.
if [[ -z "$CONTAINER_RUNTIME" || "$CONTAINER_RUNTIME" == 'docker' ]] ; then
  if ! wait_cmd_success 'if [ -z "$(sudo docker ps -q --filter '\''name=k8s_POD_kube-apiserver*'\'')" ]; then false; fi' 5 12 ; then
    echo "ERROR: Kubernetes API POD is not available"
    exit 1
  fi
else
  # TODO: fix it for non-docker
  sleep 20
fi

if ! wait_cmd_success "is_kubeapi_accessible ${masters[0]}" 5 12 ; then
  echo "ERROR: Kubernetes API is not accessible"
  exit 1
fi
if [[ "openstack" == "${ORCHESTRATOR}" && "${CNI}" == "calico" ]]; then
  # NB. calico requires custom mtu settings when network is over vxlan
  # because of an extra packet header otherwise packet loss is observed.
  # this is what we have in some openstack providers.
  k=/usr/local/bin/kubectl
  echo "INFO: Wait for calico-node daemonset"
  wait_cmd_success "$k -n kube-system get daemonset/calico-node" 5 36

  echo "INFO: Patch calico-node daemonset"
  $k -n kube-system patch daemonset/calico-node --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "FELIX_IPINIPMTU", "value": "1400"}}]'
  $k -n kube-system patch daemonset/calico-node --type='json' -p='[{"op": "add", "path": "/spec/template/spec/initContainers/0/env/-", "value": {"name": "CNI_MTU", "value": "1400"}}]'
  $k rollout restart daemonset calico-node -n kube-system

  echo "Patch calico CNI template on all nodes"
  for machine in $(echo "$CONTROLLER_NODES $AGENT_NODES" | tr " " "\n" | sort -u); do
    echo "INFO: Patch calico CNI template at $machine"
    ssh $ssh_opts $machine <<'PATCH'
sudo sed --in-place=.backup -re 's!^(\s*)("log_level":.*)$!\1\2\n\1"mtu": __CNI_MTU__,!'  /etc/cni/net.d/calico.conflist.template
PATCH
  done

  echo "INFO: Patch calico-node pods"
  $k -n kube-system delete pods --selector k8s-app=calico-node
fi

cd ../
