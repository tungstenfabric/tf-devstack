#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

command juju config kubernetes-master \
    authorization-mode="Node,RBAC" \
    enable-keystone-authorization=true \
    keystone-policy="$(cat $my_dir/files/k8s_policy.yaml)"

keystone_address=$(juju status --format json | jq '.applications["keystone"]["units"][]["public-address"]' | sed 's/"//g' | sed 's/\n//g')

# the keystone should listen on vhost0 network
# we need the reachability between keystone and keystone auth pod via vhost0 interface
sudo iptables -A OUTPUT -t nat -p tcp --dport  5000 -j DNAT --to $keystone_address:5000
sudo iptables -A OUTPUT -t nat -p tcp --dport 35357 -j DNAT --to $keystone_address:35357
sudo iptables -A FORWARD -p tcp --dport  5000 -j ACCEPT
sudo iptables -A FORWARD -p tcp --dport 35357 -j ACCEPT

keystone_machine=$(juju status --format json | jq '.applications["keystone"]["units"][]["machine"]' | sed 's/"//g' | awk -F '/' '{print$1}')
jq_request=".machines[\"$keystone_machine\"][\"ip-addresses\"][]"
host_address=$(juju status --format json | jq "$jq_request" | head -n 1 | sed 's/"//g')
command juju config keystone os-public-hostname=$host_address
