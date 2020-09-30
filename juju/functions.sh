#!/bin/bash

# lp:1616098 Pick reachable address among all
function get_juju_unit_ips(){
  local unit=$1
  local unit_list="`command juju status | grep "$unit" | grep "/" | tr -d "*" | awk '{print $1}'`"
  local machine_ips
  local u
  local ip
  local ips
    for u in $unit_list; do
      unit_machine="`command juju show-unit --format json $u | jq -r .[].machine`"
      machine_ips="`command juju show-machine --format json $unit_machine | jq -r '.machines[]."ip-addresses"[]'`"
      if  [[ "`echo $machine_ips | wc -w`" == 1 ]] ; then
        ips+=" $machine_ips"
      else
        for ip in $machine_ips ; do
          if nc -z $ip 22; then
            ips+=" $ip"
            break
          fi
        done
      fi
    done
  echo $ips
}
