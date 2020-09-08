#!/bin/bash -xe

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

export OPENSTACK_RELEASE=${OPENSTACK_VERSION:-rocky}
export OSH_OPENSTACK_RELEASE=${OPENSTACK_RELEASE}
# Disable checks for openstack compute-kit after setup
export TF_DEPLOYMENT=yes
# Disable compute-kit tests
export RUN_HELM_TESTS=no

[ "$(whoami)" == "root" ] && echo "Please run script as non-root user" && exit 1

# install and remove deps and other prereqs
if [ "$DISTRO" == "centos" ]; then
  sudo yum remove -y pyparsing
  [[ $(sudo service firewalld stop) ]] || true
  sudo yum install -y epel-release
  sudo yum install -y wget jq nmap bc python-pip python-devel git gcc nfs-utils libffi-devel openssl-devel
elif [ "$DISTRO" == "ubuntu" ]; then
  export DEBIAN_FRONTEND=noninteractive
  sudo -E apt-get install -y jq python3-pip libffi-dev libssl-dev nfs-common
fi

label_nodes_by_ip openstack-control-plane=enabled $CONTROLLER_NODES
label_nodes_by_ip openstack-compute-node=enabled $AGENT_NODES

# get openstack-helm and openstach-helm-infra
[ ! -d "$WORKSPACE/openstack-helm-infra" ] && git clone http://github.com/openstack/openstack-helm-infra $WORKSPACE/openstack-helm-infra
[ ! -d "$WORKSPACE/openstack-helm" ] && git clone http://github.com/openstack/openstack-helm $WORKSPACE/openstack-helm

# build infra charts
helm init -c
cd $WORKSPACE/openstack-helm-infra

function kill_helm_serve() {
  (pgrep -f "helm serve" | xargs -n1 -r kill) || :
}

trap 'catch_errors' ERR
function catch_errors() {
  local exit_code=$?
  kill_helm_serve
  exit $exit_code
}

kill_helm_serve
helm serve &
sleep 5
helm repo add local http://localhost:8879/charts

# TODO: set coredns replicas=1 if one node
make helm-toolkit
make nfs-provisioner

# Install openstack CLI not using standard openstack-helm script due to errors in pip3.
# The errors are lead to Segmantation fault if try to use standard scripts with kubespray k8s
sudo -H -E pip3 install \
  -c${UPPER_CONSTRAINTS_FILE:=https://releases.openstack.org/constraints/upper/master} \
  cmd2 python-openstackclient python-heatclient --ignore-installed --no-binary :all:

sudo -H mkdir -p /etc/openstack
sudo -H chown -R $(id -un): /etc/openstack
tee /etc/openstack/clouds.yaml << EOF
clouds:
  openstack_helm:
    region_name: RegionOne
    identity_api_version: 3
    auth:
      username: 'admin'
      password: 'password'
      project_name: 'admin'
      project_domain_name: 'default'
      user_domain_name: 'default'
      auth_url: 'http://keystone.openstack.svc.cluster.local/v3'
EOF

cd $WORKSPACE/openstack-helm

# run deploy scripts
export FEATURE_GATES=tf

#NOTE: Build helm-toolkit, most charts depend on helm-toolkit
make helm-toolkit

./tools/deployment/component/common/ingress.sh
./tools/deployment/component/common/mariadb.sh
./tools/deployment/component/common/memcached.sh
./tools/deployment/component/common/rabbitmq.sh
./tools/deployment/component/nfs-provisioner/nfs-provisioner.sh
./tools/deployment/component/keystone/keystone.sh
./tools/deployment/component/heat/heat.sh
./tools/deployment/component/glance/glance.sh
./tools/deployment/component/compute-kit/tungsten-fabric.sh prepare
./tools/deployment/component/compute-kit/libvirt.sh
./tools/deployment/component/compute-kit/compute-kit.sh

kill_helm_serve
