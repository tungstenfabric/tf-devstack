#!/bin/bash -e

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
  local sudo_cmd=""
  [ "$(whoami)" != "root" ] && sudo_cmd="sudo"
  $sudo_cmd rm -rf "$WORKSPACE/$DEPLOYER_DIR"
  ensure_insecure_registry_set $CONTAINER_REGISTRY
  $sudo_cmd docker create --name $DEPLOYER_IMAGE $CONTAINER_REGISTRY/$DEPLOYER_IMAGE:$CONTRAIL_CONTAINER_TAG
  $sudo_cmd docker cp $DEPLOYER_IMAGE:$DEPLOYER_DIR $WORKSPACE
  $sudo_cmd docker rm -fv $DEPLOYER_IMAGE
  $sudo_cmd chown -R $USER "$WORKSPACE/$DEPLOYER_DIR"
}

function wait_cmd_success() {
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}
  local i=0
  while ! $cmd 2>/dev/null; do
      printf "."
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

function set_ssh_keys() {
  [ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
  [ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
  [ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
  grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
}
