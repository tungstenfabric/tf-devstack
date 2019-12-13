#!/bin/bash -xe

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

TF_HELM_FOLDER=${TF_HELM_FOLDER:-tf-helm-deployer}
TF_HELM_URL=${TF_HELM_URL:-https://github.com/tungstenfabric/tf-helm-deployer}
ORCHESTRATOR=${ORCHESTRATOR:-"openstack"}

if [ "$ORCHESTRATOR" == "kubernetes" ]; then
  CONTRAIL_CHART="contrail-k8s"
else
  CONTRAIL_CHART="contrail"
fi

if [ ! -d "$TF_HELM_FOLDER" ] ; then
    git clone "$TF_HELM_URL" "$TF_HELM_FOLDER"
fi

# label nodes
label_nodes_by_ip opencontrail.org/vrouter-kernel=enabled $AGENT_NODES

cd tf-helm-deployer

helm init --client-only

# install plugin to make helm work without CNI
if [ "$ORCHESTRATOR" == "kubernetes" ]; then
  kubectl -n kube-system scale deployment tiller-deploy --replicas=0
  helm plugin install https://github.com/rimusz/helm-tiller || :
  helm tiller stop >/dev/null &2>&1 || :
  export HELM_HOST=127.0.0.1:44134
  helm tiller start-ci
fi

function kill_helm_serve() {
  if [ "$ORCHESTRATOR" == "kubernetes" ]; then
    helm tiller stop >/dev/null &2>&1 || :
  fi
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
make all

# Refactor for AGENT_NODES and CONTROLLER_NODES
# Mark controller after vrouter installed
for node in $(kubectl get nodes --no-headers | cut -d' ' -f1); do
  kubectl label node --overwrite $node opencontrail.org/controller-
done

# Refactor BGP_PORT for OpenStack and Kubernetes modes
cat << EOF > tf-devstack-values.yaml
global:
  contrail_env:
    CONTROLLER_NODES: "$(echo $CONTROLLER_NODES | tr ' ' ',')"
    JVM_EXTRA_OPTS: "-Xms1g -Xmx2g"
    BGP_PORT: "1179"
    CONFIG_DATABASE_NODEMGR__DEFAULTS__minimum_diskGB: "2"
    DATABASE_NODEMGR__DEFAULTS__minimum_diskGB: "2"
  node:
    host_os: $DISTRO
EOF

if [ "$DISTRO" == "centos" ]; then
  [[ $(sudo service firewalld stop) ]] || true
  # Determine kuberenetes dns and add it with searchdomains to dhclient.conf
  # because NetworkManager in centos rewrites resolv.conf
  k8s_dns=$(kubectl get services -n kube-system | grep dns | awk '{print $3}')
  sudo touch /etc/dhcp/dhclient.conf
  if [[ -z $(sudo grep "$k8s_dns" /etc/dhcp/dhclient.conf) ]]; then
    echo "prepend domain-name-servers $k8s_dns;" | sudo tee -a /etc/dhcp/dhclient.conf
    echo "prepend domain-search \"default.svc.cluster.local\", \"svc.cluster.local\";" | sudo tee -a /etc/dhcp/dhclient.conf
  fi
else
  host_var=""
fi

sudo mkdir -p /var/log/contrail

kubectl create ns tungsten-fabric || :
helm upgrade --install --namespace tungsten-fabric tungsten-fabric $CONTRAIL_CHART -f tf-devstack-values.yaml $host_var

if [ "$ORCHESTRATOR" == "kubernetes" ]; then
  kubectl -n kube-system scale deployment tiller-deploy --replicas=1
fi

wait_nic_up vhost0
label_nodes_by_ip opencontrail.org/controller=enabled $CONTROLLER_NODES

trap - ERR
kill_helm_serve

echo "Contrail Web UI will be available at any IP(or name) from '$CONTROLLER_NODES': https://IP:8143"
