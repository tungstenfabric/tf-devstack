#!/bin/bash -xe

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"
source "$my_dir/functions.sh"

# parameters

HELM_OPENSTACK_URL=${HELM_OPENSTACK_URL:-https://review.opendev.org/changes/663390/revisions/ce7ee2188228d6ab3ff6aaaa6ab5ba0cd1717ba1/archive?format=tgz}
#HELM_OPENSTACK_INFRA_URL=https://github.com/openstack/openstack-helm-infra/archive/24c1cd4514384fe22f3a882d41cf927588b03f2b.tar.gz
export OPENSTACK_RELEASE=${OPENSTACK_VERSION:-queens}
export OSH_OPENSTACK_RELEASE=${OPENSTACK_RELEASE}

[ "$(whoami)" == "root" ] && echo Please run script as non-root user && exit

# install and remove deps and other prereqs
if [ "$DISTRO" == "centos" ]; then
    sudo yum remove -y pyparsing
    [[ $(sudo service firewalld stop) ]] || true
    sudo yum install -y epel-release
    sudo yum install -y wget jq nmap bc python-pip python-devel git gcc nfs-utils
elif [ "$DISTRO" == "ubuntu" ]; then
  sudo apt-get install --no-install-recommends -y \
        wget ca-certificates git make jq nmap curl uuid-runtime bc python-pip python-dev nfs-common
fi
sudo -H pip install -U pip wheel
sudo -H pip install --user wheel yq

# label nodes
label_nodes_by_ip openstack-control-plane=enabled $CONTROLLER_NODES
label_nodes_by_ip openstack-compute-node=enabled $AGENT_NODES

# fetch helm-openstack
wget $HELM_OPENSTACK_URL -O helm-openstack.tgz
#wget $HELM_OPENSTACK_INFRA_URL -O helm-openstack-infra.tgz
mkdir -p openstack-helm openstack-helm-infra
tar xzf helm-openstack.tgz -C openstack-helm
#tar xzf helm-openstack-infra.tgz --strip-components=1 -C openstack-helm-infra
git clone http://github.com/openstack/openstack-helm-infra

# add TF overrides
cp $my_dir/../helm/files/libvirt-tf.yaml openstack-helm-infra/libvirt/values_overrides/tf.yaml
cp $my_dir/../helm/files/nova-tf.yaml openstack-helm/nova/values_overrides/tf.yaml
cp $my_dir/../helm/files/neutron-tf.yaml openstack-helm/neutron/values_overrides/tf.yaml
cp $my_dir/../helm/files/keystone-tf.yaml openstack-helm/keystone/values_overrides/tf.yaml
sed -i "s/openstack_version:.*$/openstack_version: $OSH_OPENSTACK_RELEASE/" openstack-helm/neutron/values_overrides/tf.yaml

# build infra charts
helm init -c
cd openstack-helm-infra
[ $(pgrep -f "helm serve" | xargs -n1 -r kill) ] || true
helm serve &
sleep 5
helm repo add local http://localhost:8879/charts
make helm-toolkit

export FEATURE_GATES=tf

# TODO: set coredns replicas=1 if one node
cd ../openstack-helm-infra
make helm-toolkit
make nfs-provisioner

# label nodes
for node in $(kubectl get nodes --no-headers | cut -d' ' -f1 | head -1); do
  kubectl label node $node --overwrite openstack-control-plane=enabled
done
for node in $(kubectl get nodes --no-headers | cut -d' ' -f1); do
  kubectl label node $node --overwrite openstack-compute-node=enabled
done

cd ../openstack-helm
./tools/deployment/developer/common/020-setup-client.sh
./tools/deployment/developer/common/030-ingress.sh
./tools/deployment/developer/nfs/040-nfs-provisioner.sh
./tools/deployment/developer/nfs/050-mariadb.sh
./tools/deployment/developer/nfs/060-rabbitmq.sh
./tools/deployment/developer/nfs/070-memcached.sh
./tools/deployment/developer/nfs/080-keystone.sh
# Heat is not really supported by TF now
#./tools/deployment/developer/nfs/090-heat.sh
./tools/deployment/developer/nfs/120-glance.sh
./tools/deployment/developer/nfs/150-libvirt.sh
echo "Running nova/neutron deploy in the background"
./tools/deployment/developer/nfs/160-compute-kit.sh &

cd ../..
