#!/bin/bash

fmy_file="${BASH_SOURCE[0]}"
fmy_dir="$(dirname $fmy_file)"

function ensure_kube_api_ready() {
  if ! wait_cmd_success "kubectl get nodes" 3 40 ; then
    echo "ERROR: kubernetes is not ready. Exiting..."
    return 1
  fi
}

# pull deployer src container locally and extract files to path
# Functions get two required params:
#  - deployer image
#  - directory path deployer have to be extracted to
function fetch_deployer() {
  if [[ $# != 2 ]] ; then
    echo "ERROR: Deployer image name and path to deployer directory are required for fetch_deployer"
    return 1
  fi

  local deployer_image=$1
  local deployer_dir=$2

  sudo rm -rf $deployer_dir

  local image="$DEPLOYER_CONTAINER_REGISTRY/$deployer_image"
  [ -n "$CONTRAIL_DEPLOYER_CONTAINER_TAG" ] && image+=":$CONTRAIL_DEPLOYER_CONTAINER_TAG"
  sudo docker create --name $deployer_image --entrypoint /bin/true $image || return 1
  sudo docker cp $deployer_image:/src $deployer_dir
  sudo docker rm -fv $deployer_image
  sudo chown -R $UID $deployer_dir
}

function fetch_deployer_no_docker() {
  if [[ $# != 2 ]] ; then
    echo "ERROR: Deployer image name and path to deployer directory are required for fetch_deployer"
    return 1
  fi
  local deployer_image=$1
  local deployer_dir=$2
  local tmp_deployer_layers_dir="$(mktemp -d)"
  local archive_tmp_dir="$(mktemp -d)"
  if ! ${fmy_dir}/download-frozen-image-v2.sh $tmp_deployer_layers_dir ${deployer_image}:${CONTRAIL_DEPLOYER_CONTAINER_TAG} ; then
    echo "ERROR: Image could not be downloaded."
    return 1
  fi
  tar xf ${tmp_deployer_layers_dir}/$(cat ${tmp_deployer_layers_dir}/manifest.json | jq --raw-output '.[0].Layers[0]') -C ${archive_tmp_dir}
  rm -rf $deployer_dir
  if [[ ! -d "${archive_tmp_dir}/src" ]] ; then
    echo "ERROR: No src folder in ${archive_tmp_dir}/src. Exit"
    return 1
  fi
  mv ${archive_tmp_dir}/src $deployer_dir
}

function wait_cmd_success() {
  # silent mode = don't print output of input cmd for each attempt.
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}
  local silent_cmd=${4:-1}

  local state="$(set +o)"
  [[ "$-" =~ e ]] && state+="; set -e"

  set +o xtrace
  set -o pipefail
  local i=0
  if [[ "$silent_cmd" != "0" ]]; then
    local to_dev_null="&>/dev/null"
  else
    local to_dev_null=""
  fi
  while ! eval "$cmd" "$to_dev_null"; do
    printf "."
    i=$((i + 1))
    if (( i > max )) ; then
      echo ""
      echo "ERROR: wait failed in $((i*interval))s"
      eval "$cmd"
      eval "$state"
      return 1
    fi
    sleep $interval
  done
  echo ""
  echo "INFO: done in $((i*interval))s"
  eval "$state"
}

function wait_nic_up() {
  local nic=$1
  printf "INFO: wait for $nic is up"
  if ! wait_cmd_success "nic_has_ip $nic" 10 60; then
    echo "ERROR: $nic is not up"
    return 1
  fi
  echo "INFO: $nic is up"
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
  local node_ips=$(echo $* | tr ' ' '\n')
  wait_cmd_success "kubectl get nodes --no-headers" 5 2
  for node in $(kubectl get nodes --no-headers | cut -d ' ' -f 1) ; do
    local nodeip=$(kubectl get node $node -o=jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    if echo $node_ips | grep -wF $nodeip; then
      kubectl label node --overwrite $node $label
    fi
  done
}

function check_pods_active() {
  local tool=${1:-kubectl}
  declare -a pods
  readarray -t pods < <($tool get pods --all-namespaces --no-headers)

  if [[ ${#pods[@]} == '0' ]]; then
    return 1
  fi

  #check if all pods are running
  local pod
  for pod in "${pods[@]}" ; do
    local status="$(echo $pod | awk '{print $4}')"
    if [[ "$status" == 'Completed' ]]; then
      continue
    elif [[ "$status" != "Running" ]] ; then
      return 1
    else
      local containers_running=$(echo $pod | awk '{print $3}' | cut -f 1 -d '/')
      local containers_total=$(echo $pod | awk '{print $3}' | cut -f 2 -d '/')
      if [ "$containers_running" != "$containers_total" ] ; then
        return 1
      fi
    fi
  done
  return 0
}

function check_kubernetes_resources_active() {
  # possible values: statefulset.apps deployment.apps
  # zero output of kubectl is treated as fail!
  local resource=$1
  local tool=${2:-kubectl}
  declare -a items
  readarray -t items < <($tool get $resource --all-namespaces --no-headers)

  if [[ ${#items[@]} == '0' ]]; then
    return 1
  fi

  #check if all pods are running
  local item
  for item in "${items[@]}" ; do
    local running=$(echo $item | awk '{print $3}' | cut -f 1 -d '/')
    local total=$(echo $item | awk '{print $3}' | cut -f 2 -d '/')
    if [ "$running" != "$total" ] ; then
      return 1
    fi
  done
  return 0
}

function check_pod_services() {
  local pod
  eval "declare -A array="${1#*=}
  for pod in "${!array[@]}"; do
    local pod_name=$pod
    if [[ "$pod" == '_' ]]; then
      pod_name=''
    fi
    local service
    for service in ${array[$pod]} ; do
      if ! grep -q "$pod_name[ \t]*$service[ \t]*" /tmp/_tmp_contrail_status; then
        echo "ERROR: pod '$pod_name's service '$service' is missing in contrail-status of $2"
        return 1
      fi
    done
  done

  return 0
}

function check_tf_services() {
  local user=${1:-$SSH_USER}
  local controller_nodes=${2-$CONTROLLER_NODES}
  local agent_nodes=${3-$AGENT_NODES}
  local nodes="$controller_nodes $agent_nodes"
  local machine

  for machine in $(echo "$nodes" | tr " " "\n" | sort -u) ; do
    local addr="$machine"
    [ -z "$user" ] || addr="$user@$addr"
    if ! ssh $SSH_OPTIONS $addr "command -v contrail-status" 2>/dev/null ; then
      return 1
    fi

    # get contrail-status from $machine node
    # TODO: set timeout 15 sec (-t 15) - there is bug in agent - it does internally
    #       2 dns queries with 5 sec timeout that always fails in 10 sec,
    #       so tool always fails with default 10 sec timeout. 
    local contrail_status=$(ssh $SSH_OPTIONS $addr "sudo contrail-status -t 15" 2>/dev/null)
    # keep first part of contrail-status with rows and columns
    # of pods and services in /tmp/_tmp_contrail_status file
    # TODO: either use random name or store this info in variable
    echo "$contrail_status" | sed -n '/^$/q;p' | sed '1d' > /tmp/_tmp_contrail_status

    if [[ " $controller_nodes " =~ " $machine " ]]; then
      if ! check_pod_services "$(declare -p CONTROLLER_SERVICES)" $addr ; then
        rm /tmp/_tmp_contrail_status
        return 1
      fi
    fi

    if [[ " $agent_nodes " =~ " $machine " ]]; then
      if ! check_pod_services "$(declare -p AGENT_SERVICES)" $addr ; then
        rm /tmp/_tmp_contrail_status
        return 1
      fi
    fi
  done
  rm /tmp/_tmp_contrail_status
  return 0
}

function check_tf_active() {
  local user=${1:-$SSH_USER}
  shift || true
  local nodes="${@:-$CONTROLLER_NODES $AGENT_NODES}"
  local machine
  local line=
  for machine in $(echo "$nodes" | tr " " "\n" | sort -u) ; do
    local addr="$machine"
    [ -z "$user" ] || addr="$user@$addr"
    if ! ssh $SSH_OPTIONS $addr "command -v contrail-status" 2>/dev/null ; then
      return 1
    fi
    # TODO: set timeout 15 sec (-t 15) - there is bug in agent - it does internally
    #       2 dns queries with 5 sec timeout that always fails in 10 sec,
    #       so tool always fails with default 10 sec timeout. 
    for line in $(ssh $SSH_OPTIONS $addr "sudo contrail-status -t 15" 2>/dev/null | egrep ": " | grep -v "WARNING" | awk '{print $2}'); do
      if [ "$line" != "active" ] && [ "$line" != "backup" ] ; then
        return 1
      fi
    done
  done
  return 0
}

#TODO time sync restart needed when startup from snapshot
function setup_timeserver() {
  # install timeserver
  if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
    if [[ ! "$DISTRO_VERSION_ID" =~ ^8\. ]] ; then
      sudo yum install -y ntp
      sudo systemctl enable ntpd
      sudo systemctl start ntpd
    else
      #rhel8.x
      sudo yum install -y chrony
    fi
  elif [ "$DISTRO" == "ubuntu" ]; then
    DEBIAN_FRONTEND=noninteractive
    # Check for Ubuntu 18
    sudo apt update -y

    local ubuntu_release=`lsb_release -r | awk '{split($2,a,"."); print a[1]}'`
    if [ 16 -eq $ubuntu_release ]; then
      sudo apt install -y ntp
    else # Ubuntu 18 or more
      sudo apt install -y chrony
    fi
  else
    echo "Unsupported OS version"
    return 1
  fi
}

function retry() {
  local i
  for ((i=0; i<10; ++i)) ; do
    if $@ ; then
      return 0
    fi
    sleep 6
  done

  return 1
}

function sync_time() {
  if [[ "$DEPLOYER" == 'openshift3' ]]; then
    # skip it for openshift3
    return
  fi

  local user=${1:-$SSH_USER}
  shift || true
  local nodes="${@:-$CONTROLLER_NODES $AGENT_NODES $OPENSTACK_CONTROLLER_NODES}"
  echo "INFO: check time sync on nodes and force sync $(date)"
  echo "INFO: controller nodes - $CONTROLLER_NODES"
  echo "INFO: agent nodes - $AGENT_NODES"
  echo "INFO: openstack controller nodes - $OPENSTACK_CONTROLLER_NODES"

  local machine
  for machine in $(echo $nodes | tr " " "\n" | sort -u) ; do
    local addr="$machine"
    [ -z "$user" ] || addr="$user@$addr"
    echo "INFO: sync time on machine $addr"
    scp $SSH_OPTIONS ${fmy_dir}/sync_time.sh ${addr}:/tmp/sync_time.sh
    ssh $SSH_OPTIONS ${addr} DEBUG=$DEBUG /tmp/sync_time.sh
  done
}

function ensureVariable() {
  local env_var=$(declare -p "$1")
  if !  [[ -v $1 && $env_var =~ ^declare\ -x ]]; then
    echo "Error: Define $1 environment variable"
    exit 1
  fi
}

function get_vrouter_gateway() {
    local cidr=${1:-${DATA_NETWORK}}
    [ -n "$cidr" ] || return
    local gw=$(ip route get "$cidr" | grep -o 'via .*' |  awk '{print($2)}' |head -n1)
    [ -z "$gw" ] || echo $gw
}
