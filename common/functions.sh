#!/bin/bash

function ensure_root() {
  local me=$(whoami)
  if [ "$me" != 'root' ] ; then
    echo "ERROR: this script requires root, run it like this:"
    echo "       sudo -E $0"
    exit 1;
  fi
}

function check_docker_value() {
  local name=$1
  local value=$2
  python -c "import json; f=open('/etc/docker/daemon.json'); data=json.load(f); print(data.get('$name'));" 2>/dev/null| grep -qi "$value"
}

function ensure_insecure_registry_set() {
  local registry=$1
  local sudo_cmd=""
  [ "$(whoami)" != "root" ] && sudo_cmd="sudo"
  registry=`echo $registry | sed 's|^.*://||' | cut -d '/' -f 1`
  if ! curl -s -I --connect-timeout 5 http://$registry/v2/ ; then
    # dockerhub is used or server doesn't respond by http. skip adding to insecure
    return
  fi
  if check_docker_value "insecure-registries" "${registry}" ; then
    # already set
    return
  fi

  $sudo_cmd python <<EOF
import json
data=dict()
try:
  with open("/etc/docker/daemon.json") as f:
    data = json.load(f)
except Exception:
  pass
data.setdefault("insecure-registries", list()).append("${registry}")
with open("/etc/docker/daemon.json", "w") as f:
  data = json.dump(data, f, sort_keys=True, indent=4)
EOF
  if [ x"$DISTRO" == x"centos" ]; then
    $sudo_cmd systemctl restart docker
  elif [ x"$DISTRO" == x"ubuntu" ]; then
    $sudo_cmd service docker reload
  fi
}

function ensure_kube_api_ready() {
  if ! wait_cmd_success "kubectl get nodes" 3 40 ; then
    echo "ERROR: kubernetes is not ready. Exiting..."
    exit 1
  fi
}

function fetch_deployer() {
  sudo rm -rf "$WORKSPACE/$DEPLOYER_DIR"
  ensure_insecure_registry_set $CONTAINER_REGISTRY
  local image="$CONTAINER_REGISTRY/$DEPLOYER_IMAGE"
  [ -n "$CONTRAIL_CONTAINER_TAG" ] && image+=":$CONTRAIL_CONTAINER_TAG"
  sudo docker create --name $DEPLOYER_IMAGE --entrypoint /bin/true $image
  sudo docker cp $DEPLOYER_IMAGE:$DEPLOYER_DIR - | tar -x -C $WORKSPACE
  sudo docker rm -fv $DEPLOYER_IMAGE
}

function wait_cmd_success() {
  # silent mode = don't print dots for each attempt. Just print command output
  set -o pipefail
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}
  local silent=${4:-1}
  local i=0
  if [[ "$silent" != "0" ]]; then
    local to_dev_null="&>/dev/null"
  else
    local to_dev_null=""
  fi
  while ! eval "$cmd" "$to_dev_null"; do
    if [[ "$silent" != "0" ]]; then
      printf "."
    fi
    i=$((i + 1))
    if (( i > max )) ; then
      return 1
    fi
    sleep $interval
  done
}

function wait_nic_up() {
  local nic=$1
  printf "INFO: wait for $nic is up"
  wait_cmd_success "nic_has_ip $nic" || { echo -e "\nERROR: $nic is not up" && return 1; }
  echo -e "\nINFO: $nic is up"
}

function nic_has_ip() {
  local nic=$1
  if nic_ip=$(ip addr show $nic | grep -o "inet [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*"); then
    printf "\n$nic has IP $nic_ip"
    return 0
  else
    return 1
  fi
}

function set_ssh_keys() {
  [ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
  [ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
  [ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
  grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
}

function label_nodes_by_ip() {
  local label=$1
  shift
  local node_ips=$*
  local retries=5
  local interval=2
  local silent=0
  for node in $(wait_cmd_success "kubectl get nodes --no-headers" $retries $interval $silent | cut -d' ' -f1 ); do
    local nodeip=$(wait_cmd_success "kubectl get node $node -o=jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}'" $retries $interval $silent)
    if echo $node_ips | tr ' ' '\n' | grep -F $nodeip; then
      wait_cmd_success "kubectl label node --overwrite $node $label" $retries $interval $silent
    fi
  done
}

function check_pods_active() {
  declare -a pods
  readarray -t pods < <( kubectl get pods   --all-namespaces  | grep contrail   )

  #check if all pods are running
  for pod in "${pods[@]}" ; do
    if [ "$( echo $pod | awk '{print $4}')" != "Running" ] ; then
      return 1
    else
      containers_running=$(echo $pod  | awk '{print $3}' | cut  -f1 -d/ )
      containers_total=$(echo $pod  | awk '{print $3}' | cut  -f2 -d/ )
      if [ "$containers_running" != "$containers_total" ] ; then
        return 1
      fi
    fi
  done
  return 0
}

function check_tf_active() {
  local line=
  for line in $(sudo contrail-status | egrep ": " | awk '{print $2}'); do
    if [ "$line" != "active" ] && [ "$line" != "backup" ] ; then
      return 1
    fi
  done
  return 0
}
