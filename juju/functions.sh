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
