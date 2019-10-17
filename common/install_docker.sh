#!/bin/bash -e

# This script doesn't care about insecure-registies

my_file="$(readlink -e "$0")"
my_dir="$(dirname "$my_file")"
source "$my_dir/common.sh"

function install_docker_ubuntu() {
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  add-apt-repository -y -u "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get install -y "docker-ce=18.06.3~ce~3-0~ubuntu"
}

function install_docker_centos() {
  yum install -y yum-utils device-mapper-persistent-data lvm2
  if ! yum info docker-ce &> /dev/null ; then
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  fi
  yum install -y docker-ce-18.03.1.ce
}

function install_docker_rhel() {
  subscription-manager repos \
    --enable rhel-7-server-extras-rpms \
    --enable rhel-7-server-optional-rpms
  yum install -y docker device-mapper-libs device-mapper-event-libs
}

function check_docker_value() {
  local name=$1
  local value=$2
  python -c "import json; f=open('/etc/docker/daemon.json'); data=json.load(f); print(data.get('$name'));" 2>/dev/null| grep -qi "$value"
}

echo
echo '[docker install]'
echo $DISTRO detected.
if [ x"$DISTRO" == x"centos" ]; then
  which docker || install_docker_centos
  systemctl start docker
  systemctl stop firewalld || true
elif [ x"$DISTRO" == x"rhel" ]; then
  which docker || install_docker_rhel
  systemctl start docker
  systemctl stop firewalld || true
elif [ x"$DISTRO" == x"ubuntu" ]; then
  which docker || install_docker_ubuntu
fi
mkdir -p /etc/docker
touch /etc/docker/daemon.json

echo
echo '[docker setup]'
default_iface=`ip route get 1 | grep -o "dev.*" | awk '{print $2}'`
default_iface_mtu=`ip link show $default_iface | grep -o "mtu.*" | awk '{print $2}'`

docker_reload=0
if ! check_docker_value mtu "$default_iface_mtu" || ! check_docker_value "live-restore" "true" ; then
  python <<EOF
import json
data=dict()
try:
  with open("/etc/docker/daemon.json") as f:
    data = json.load(f)
except Exception:
  pass
data["mtu"] = $default_iface_mtu
data["live-restore"] = True
with open("/etc/docker/daemon.json", "w") as f:
  data = json.dump(data, f, sort_keys=True, indent=4)
EOF
  docker_reload=1
fi

runtime_docker_mtu=`sudo docker network inspect --format='{{index .Options "com.docker.network.driver.mtu"}}' bridge`
if [[ "$default_iface_mtu" != "$runtime_docker_mtu" || "$docker_reload" == '1' ]]; then
  if [ x"$distro" == x"centos" ]; then
    systemctl restart docker
  elif [ x"$distro" == x"ubuntu" ]; then
    service docker reload
  fi
fi
