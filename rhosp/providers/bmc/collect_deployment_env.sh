#!/bin/bash -e

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/functions.sh"

if [ -f ~/rhosp-environment.sh ]; then
   source ~/rhosp-environment.sh
else
   echo "File ~/rhosp-environment.sh not found"
   exit
fi

if [ -f ~/stackrc ]; then
   source ~/stackrc
else
   echo "File ~/stackrc not found"
   exit
fi

if [[ "$DEPLOY_COMPACT_AIO" == "true" ]] ; then
    CONTROLLER_NODES=$(get_servers_ips_by_flavor control)
    AGENT_NODES="$CONTROLLER_NODES"
else
    CONTROLLER_NODES=$(get_servers_ips_by_flavor contrail-controller)
    AGENT_NODES=$(get_servers_ips_by_flavor compute)
fi

if [[ -f ~/overcloudrc ]]; then
    source ~/overcloudrc
    CONTROLLER_NODE=$(echo ${CONTROLLER_NODES} | awk '{print $1}')
    internal_vip=$(ssh $ssh_opts heat-admin@$CONTROLLER_NODE sudo hiera -c /etc/puppet/hiera.yaml internal_api_virtual_ip)
    os_auth_internal_api_url=$(echo $OS_AUTH_URL | sed "s#[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+#$internal_vip#")

    echo "export CONTROLLER_NODES='${CONTROLLER_NODES}'" > ~/deployment.env
    echo "export AGENT_NODES='${AGENT_NODES}'" >> ~/deployment.env
    echo "export os_auth_internal_api_url='${os_auth_internal_api_url}'" >> ~/deployment.env
    echo "export OS_PASSWORD='${OS_PASSWORD}'" >> ~/deployment.env
    echo "export OS_REGION_NAME='${OS_REGION_NAME}'" >> ~/deployment.env
fi
