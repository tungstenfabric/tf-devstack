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
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}
  local silent=${4:-1}
  local i=0
  if [[ "$silent" != "0" ]]; then
    to_dev_null="&>/dev/null"
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
  return 0
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
  for node in $(wait_cmd_success "kubectl get nodes --no-headers | cut -d' ' -f1" $retries $interval $silent ); do
    echo $node
    local nodeip=$(wait_cmd_success "kubectl get node $node -o=jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}'" $retries $interval $silent)
    if echo $node_ips | tr ' ' '\n' | grep -F $nodeip; then
      wait_cmd_success "kubectl label node --overwrite $node $label" $retries $interval $silent
    fi
  done
}

function load_tf_devenv_profile() {
  if [ -e "$TF_DEVENV_PROFILE" ] ; then
    echo
    echo '[load tf devenv configuration]'
    source "$TF_DEVENV_PROFILE"
    [ -n "$REGISTRY_IP" ] && CONTAINER_REGISTRY="${REGISTRY_IP}" && [ -n "$REGISTRY_PORT" ] && CONTAINER_REGISTRY+=":${REGISTRY_PORT}" || true
  else
    echo
    echo '[there is no tf devenv configuration to load]'
  fi
  # set to tungstenfabric if not set
  [ -z "$CONTAINER_REGISTRY" ] && CONTAINER_REGISTRY='tungstenfabric' || true
  [ -z "$CONTRAIL_CONTAINER_TAG" ] && CONTRAIL_CONTAINER_TAG='latest' || true
}

function save_tf_stack_profile() {
  local file=${1:-$TF_STACK_PROFILE}
  echo
  echo '[update tf stack configuration]'
  mkdir -p "$(dirname $file)"
  cat <<EOF > $file
CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG}
CONTAINER_REGISTRY=${CONTAINER_REGISTRY}
ORCHESTRATOR=${ORCHESTRATOR}
OPENSTACK_VERSION="$OPENSTACK_VERSION"
CONTROLLER_NODES="$CONTROLLER_NODES"
AGENT_NODES="$AGENT_NODES"
EOF
  echo "tf setup profile $file"
  cat ${file}
}

function wait_absence_status_for_juju_services() {
  sleep 10
  check_str=$1
  local max_iter=${2:-30}
  # waiting for services
  local iter=0
  while juju status | grep -P $check_str &>/dev/null
  do
    echo "Waiting for all service to be active - $iter/$max_iter"
    if ((iter >= max_iter)); then
      echo "ERROR: Services didn't up."
      juju status --format tabular
      return 1
    fi
    if juju status | grep "current" | grep error ; then
      echo "ERROR: Some services went to error state"
      juju status --format tabular
      return 1
    fi
    local merr=`juju status --format json | python3 -c "import sys; import json; ms = json.load(sys.stdin)['machines']; [sys.stdout.write(str(m) + '\n') for m in ms if (ms[m]['juju-status']['current'] == 'down' and ms[m]['instance-id'] == 'pending')]"`
    if [ -n "$merr" ] ; then
      echo "ERROR: Machines went to down state: "$merr
      juju status
      return 1
    fi
    sleep 30
    ((++iter))
  done
}

function juju_post_deploy() {
  echo "INFO: Waiting for services start: $(date)"

  if ! wait_absence_status_for_juju_services "executing|blocked|waiting" 45 ; then
    echo "ERROR: Waiting for services end: $(date)"
    return 1
  fi
  echo "INFO: Waiting for services end: $(date)"

  # check for errors
  if juju status | grep "current" | grep error ; then
    echo "ERROR: Some services went to error state"
    return 1
  fi

  juju status --format tabular
}
