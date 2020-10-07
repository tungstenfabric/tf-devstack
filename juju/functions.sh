#!/bin/bash

# lp:1616098 Pick reachable address among all
function get_juju_unit_ips(){
  local unit=$1

  local unit_list="`command juju status | grep "$unit" | grep "/" | tr -d "*" | awk '{print $1}'`"
  local ips
  for unit in $unit_list ; do
    unit_machine="`command juju show-unit --format json $unit | jq -r .[].machine`"
    local machine_ips="`command juju show-machine --format json $unit_machine | jq -r '.machines[]."ip-addresses"[]'`"
    if  [[ "`echo $machine_ips | wc -w`" == 1 ]] ; then
      ips+=" $machine_ips"
    else
      local ip
      for ip in $machine_ips ; do
        if nc -z $ip 22 ; then
          ips+=" $ip"
          break
        fi
      done
    fi
  done
  echo $ips
}

function create_stackrc() {
  local auth_ip=$(command juju config keystone vip)
  if [[ -z "$auth_ip" ]]; then
    auth_ip=$(command juju status $service --format tabular | grep "$keystone/" | head -1 | awk '{print $5}')
  fi
  local proto="https"
  if [[ "${SSL_ENABLE,,}" != 'true' ]] ; then
    proto="http"
  fi
  local kver=`command juju config keystone preferred-api-version`
  echo "# created by CI" > $WORKSPACE/stackrc
  if [[ "$kver" == '3' ]] ; then
    echo "export OS_AUTH_URL=$proto://$auth_ip:5000/v3" >> $WORKSPACE/stackrc
    echo "export OS_IDENTITY_API_VERSION=3" >> $WORKSPACE/stackrc
    echo "export OS_PROJECT_DOMAIN_NAME=admin_domain" >> $WORKSPACE/stackrc
    echo "export OS_USER_DOMAIN_NAME=admin_domain" >> $WORKSPACE/stackrc
    echo "export VGW_DOMAIN=admin_domain" >> $WORKSPACE/stackrc
  else
    echo "export OS_AUTH_URL=$proto://$auth_ip:5000/v2.0" >> $WORKSPACE/stackrc
    echo "export OS_IDENTITY_API_VERSION=2" >> $WORKSPACE/stackrc
    echo "export VGW_DOMAIN=default-domain" >> $WORKSPACE/stackrc
  fi
  echo "export OS_USERNAME=admin" >> $WORKSPACE/stackrc
  echo "export OS_TENANT_NAME=admin" >> $WORKSPACE/stackrc
  echo "export OS_PROJECT_NAME=admin" >> $WORKSPACE/stackrc
  echo "export OS_PASSWORD=$(command juju run --unit keystone/0 leader-get admin_passwd)" >> $WORKSPACE/stackrc
  echo "export OS_REGION_NAME=$(command juju config keystone region)" >> $WORKSPACE/stackrc
}

function get_keystone_address(){
  keystone_addresses=$(command juju config keystone os-admin-hostname)
  if [[ -z $keystone_addresses ]] ; then
      keystone_addresses=$(command juju config keystone vip)
  fi
  if [[ -z $keystone_addresses ]] ; then
    keystone_addresses=$(command juju status --format json | jq '.applications["keystone"]["units"][]["public-address"]' | sed 's/"//g' | sed 's/\n//g')
  fi
  echo $keystone_addresses | head -n 1
}

function get_service_machine(){
  service=$1
  local jq_request="".applications[\"$service\"][\"units\"][][\"machine\"]""
  machine=$(command juju status --format json | jq "$jq_request" | sed 's/"//g' | awk -F '/' '{print$1}' | head -n 1)
  echo $machine
}

function setup_keystone_auth(){
  command juju config kubernetes-master \
      authorization-mode="Node,RBAC" \
      enable-keystone-authorization=true \
      keystone-policy="$(cat $my_dir/files/k8s_policy.yaml)"

  keystone_address=$(get_keystone_address)
  if [[ -z $keystone_address ]] ; then
    exit 1
  fi

  vrouter_machine=$(get_service_machine kubernetes-worker)
  # TODO: vhost0 isn't up yet, how to detect cidr?
  vhost_cidr=$(command juju ssh $vrouter_machine "ip address show vhost0" | awk '/inet / {print $2}' | sed 's/\r//g')
  if [[ -z $vhost_cidr ]] ; then
    exit 1
  fi

  if [[ $(python3 "$my_dir/../common/check_connectivity_to_keystone.py" $vhost_cidr $keystone_address) != 'True' ]] ; then
      # the keystone should listen on vhost0 network
      # we need the reachability between keystone and keystone auth pod via vhost0 interface
      sudo iptables -A PREROUTING -t nat -p tcp --dport  5000 -j DNAT --to $keystone_address:5000
      sudo iptables -A PREROUTING -t nat -p tcp --dport 35357 -j DNAT --to $keystone_address:35357
      sudo iptables -A OUTPUT -t nat -p tcp --dport  5000 -j DNAT --to $keystone_address:5000
      sudo iptables -A OUTPUT -t nat -p tcp --dport 35357 -j DNAT --to $keystone_address:35357
      sudo iptables -A FORWARD -p tcp --dport  5000 -j ACCEPT
      sudo iptables -A FORWARD -p tcp --dport 35357 -j ACCEPT

      keystone_machine=$(get_service_machine keystone)
      jq_request=".machines[\"$keystone_machine\"][\"ip-addresses\"][]"
      host_addresses=$(command juju status --format json | jq "$jq_request" | sed 's/"//g')
      for address in $(echo $host_addresses) ; do
        if [[ $(python3 "$my_dir/../common/check_connectivity_to_keystone.py" $vhost_cidr $address) == 'True' ]] ; then
          command juju config keystone os-public-hostname=$address
          break
        fi
        exit 1
      done
  fi
}

