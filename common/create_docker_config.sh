#!/bin/bash -x

# TODO: for now supports only one insecure registry
# try to avoid embeded python snippets

my_file="$(readlink -e "$0")"
my_dir="$(dirname "$my_file")"

mkdir -p /etc/docker
docker_config=/etc/docker/daemon.json
touch $docker_config
distro=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")

# Setup Jinja2 if not installed
if ! python3 -c 'import jinja2' > /dev/null 2>&1; then
  python3 -m pip install jinja2
fi

default_iface=`ip route get 1 | grep -o "dev.*" | awk '{print $2}'`
default_iface_mtu=`ip link show $default_iface | grep -o "mtu.*" | awk '{print $2}'`
echo "INFO: MTU $default_iface_mtu detected"
export DOCKER_MTU=$default_iface_mtu
export CONFIGURE_DOCKER_LIVERESTORE=${CONFIGURE_DOCKER_LIVERESTORE:-'true'}
export DOCKER_INSECURE_REGISTRIES=$(python3 -c "import json; f=open('$docker_config'); r=json.load(f).get('insecure-registries', []); print('\n'.join(r))" 2>/dev/null)
if [[ -n "$CONTAINER_REGISTRY" ]] ; then
  registry=`echo $CONTAINER_REGISTRY | sed 's|^.*://||' | cut -d '/' -f 1`
  if  curl -s -I --connect-timeout 60 http://$registry/v2/ ; then
    DOCKER_INSECURE_REGISTRIES=$(echo -e "${DOCKER_INSECURE_REGISTRIES}\n${registry}" | grep '.\+' | sort | uniq)
  fi
fi
export DOCKER_REGISTRY_MIRRORS=$(python3 -c "import json; f=open('$docker_config'); r=json.load(f).get('registry-mirrors', []); print('\n'.join(r))" 2>/dev/null)

python3 ${my_dir}/jinja2_render.py <"${my_dir}/files/docker_daemon.json.j2" > $docker_config

cat $docker_config
