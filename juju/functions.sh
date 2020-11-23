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
  ips=$(echo "$ips" | sed 's/ /\n/g' | sort | uniq)
  echo $ips
}

function create_stackrc() {
  local auth_ip=$(command juju config keystone vip)
  if [[ -z "$auth_ip" ]]; then
    auth_ip=$(command juju status $service --format tabular | grep "keystone/" | head -1 | awk '{print $5}')
  fi
  local proto="http"
  # TODO: add detection is SSL for openstack enabled 
  local kver=`command juju config keystone preferred-api-version`
  echo "# created by CI" > $WORKSPACE/stackrc
  if [[ "$kver" == '3' ]] ; then
    echo "export OS_AUTH_URL=$proto://$auth_ip:5000/v3" >> $WORKSPACE/stackrc
    echo "export OS_IDENTITY_API_VERSION=3" >> $WORKSPACE/stackrc
    echo "export OS_PROJECT_DOMAIN_NAME=admin_domain" >> $WORKSPACE/stackrc
    echo "export OS_USER_DOMAIN_NAME=admin_domain" >> $WORKSPACE/stackrc
    echo "export VGW_DOMAIN=admin_domain" >> $WORKSPACE/stackrc
    echo "export OS_DOMAIN_NAME=admin_domain" >> $WORKSPACE/stackrc
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

function get_keystone_address() {
  local keystone_addresses=$(command juju config keystone vip)
  if [[ -z $keystone_addresses ]] ; then
    keystone_addresses=$(command juju status --format json | jq '.applications["keystone"]["units"][]["public-address"]' | sed 's/"//g' | sed 's/\n//g')
  fi
  echo $keystone_addresses | head -n 1
}

function get_service_machine() {
  local service=$1
  local jq_request=".applications[\"$service\"][\"units\"][][\"machine\"]"
  machine=$(command juju status --format json | jq "$jq_request" | sed 's/"//g' | awk -F '/' '{print$1}' | head -n 1)
  echo $machine
}

function setup_keystone_auth() {
  command juju config kubernetes-master \
      authorization-mode="Node,RBAC" \
      enable-keystone-authorization=true \
      keystone-policy="$(cat $my_dir/files/k8s_policy.yaml)"

  if [[ $CLOUD == 'maas' ]] ; then
    return
  fi

  local keystone_address=$(get_keystone_address)
  if [[ -z $keystone_address ]] ; then
    echo "ERROR: Cannot detect the keystone address. It is needed for reachabilty to keystone from keystone-auth-pods."
    exit 1
  fi

  # detect host address
  keystone_machine=$(get_service_machine keystone)
  host_address=$(command juju ssh $keystone_machine 'hostname -i')
  if [[ -z $host_address ]] ; then
    echo "ERROR: Cannot detect the host address for machine with keystone. It is needed for reachabilty to keystone from keystone-auth-pods."
    exit 1
  fi

  # the keystone should listen on vhost0 network
  # we need the reachability between keystone and keystone auth pod via vhost0 interface
  command juju ssh $keystone_machine << EOF
sudo iptables -A PREROUTING -t nat -p tcp --dport  5000 -j DNAT --to $keystone_address:5000
sudo iptables -A PREROUTING -t nat -p tcp --dport 35357 -j DNAT --to $keystone_address:35357
sudo iptables -A OUTPUT -t nat -p tcp --dport  5000 -j DNAT --to $keystone_address:5000
sudo iptables -A OUTPUT -t nat -p tcp --dport 35357 -j DNAT --to $keystone_address:35357
sudo iptables -A FORWARD -p tcp --dport  5000 -j ACCEPT
sudo iptables -A FORWARD -p tcp --dport 35357 -j ACCEPT
EOF

  command juju config keystone os-public-hostname=$host_address
  command juju config keystone os-admin-hostname=$host_address
}

function collect_logs_from_machines() {
  cat <<EOF >/tmp/logs.sh
#!/bin/bash
tgz_name=\$1
export WORKSPACE=/tmp/juju-logs
export TF_LOG_DIR=/tmp/juju-logs/logs
export SSL_ENABLE=$SSL_ENABLE
cd /tmp/juju-logs
source ./collect_logs.sh
collect_docker_logs
collect_juju_logs
collect_contrail_status
collect_system_stats
collect_contrail_logs
collect_openstack_logs
collect_kubernetes_logs
collect_kubernetes_objects_info
chmod -R a+r logs
pushd logs
tar -czf \$tgz_name *
popd
cp logs/\$tgz_name \$tgz_name
rm -rf logs
EOF
chmod a+x /tmp/logs.sh

  local machines=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | awk '{print $1}'`
  echo "INFO: machines to ssh: $machines"
  local machine=''
  for machine in $machines ; do
    echo "INFO: collecting from $machine"
    local tgz_name=`echo "logs-$machine.tgz" | tr '/' '-'`
    mkdir -p $TF_LOG_DIR/$machine
    command juju ssh $machine "mkdir -p /tmp/juju-logs"
    command juju scp $my_dir/../common/collect_logs.sh $machine:/tmp/juju-logs/collect_logs.sh
    command juju scp /tmp/logs.sh $machine:/tmp/juju-logs/logs.sh
    command juju ssh $machine /tmp/juju-logs/logs.sh $tgz_name
    command juju scp $machine:/tmp/juju-logs/$tgz_name $TF_LOG_DIR/$machine/
    pushd $TF_LOG_DIR/$machine/
    tar -xzf $tgz_name
    rm -rf $tgz_name
    popd
  done
}