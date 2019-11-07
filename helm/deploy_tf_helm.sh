#!/bin/bash -xe

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

sudo mkdir -p /var/log/contrail
TF_HELM_FOLDER=${TF_HELM_FOLDER:-tf-helm-deployer}
TF_HELM_URL=${TF_HELM_URL:-https://github.com/tungstenfabric/tf-helm-deployer}
if [ ! -d "$TF_HELM_FOLDER" ] ; then
    git clone "$TF_HELM_URL" "$TF_HELM_FOLDER"
fi
cd tf-helm-deployer

helm init --client-only
#install plugin to make helm work without CNI
if !( helm plugin list | grep -q tiller )
then
  helm plugin install https://github.com/rimusz/helm-tiller
  helm tiller start &
fi
pgrep -f "helm serve" | xargs -n1 -r kill
helm serve &
sleep 5
helm repo add local http://localhost:8879/charts
make all

# Refactor for AGENT_NODES and CONTROLLER_NODES
# Mark controller after vrouter installed

cat << EOF > tf-devstack-values.yaml
global:
  contrail_env:
    CONTROLLER_NODES: "$(echo $CONTROLLER_NODES | tr ' ' ',')"
    JVM_EXTRA_OPTS: "-Xms1g -Xmx2g"
EOF

if [ "$DISTRO" == "centos" ]; then
  [[ $(sudo service firewalld stop) ]] || true
  host_var="--set global.node.host_os=centos"
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

#disable controller to prevent it from getting up before vrouter
for node in $(kubectl get nodes --no-headers | cut -d' ' -f1); do
  kubectl label node --overwrite $node opencontrail.org/controller-
  kubectl label node --overwrite $node opencontrail.org/vrouter-kernel=enabled
done
kubectl create ns tungsten-fabric || :
helm upgrade --install --namespace tungsten-fabric tungsten-fabric contrail-k8s -f tf-devstack-values.yaml $host_var

#enable controller back
for node in $(kubectl get nodes --no-headers | cut -d' ' -f1); do
  kubectl label node --overwrite $node opencontrail.org/controller=enabled
done


#echo "Waiting for vrouter to be ready"
#kubectl -n tungsten-fabric wait daemonset --for=condition=Ready --timeout=420s -l component=contrail-vrouter-agent-kernel

# Nodes here are not yet labelled for controller which allows vrouter to be installed.
# Labelling for controller is done in startup.sh
