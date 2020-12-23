#!/bin/bash

[[ "$DEBUG" == true ]] && set -x

function chrony_sync() {
  local out="$(chronyc -n sources)"
  if ! echo "$out" | grep -q "^\^\*" ; then
    echo "INFO: time is not synced, force it"
    echo "$out"
    sudo systemctl stop chronyd.service
    local cfg_file='/etc/chrony.conf'
    [ -e "$cfg_file" ] || cfg_file='/etc/chrony/chrony.conf'
    local server
    for server in $(grep "^server " | awk '{print $2}') ; do
      sudo chronyd -q server $server iburst
    done
    sudo systemctl start chronyd.service
    return 1
  fi
}

function ntp_sync() {
  local out="$(/usr/sbin/ntpq -n -c pe)"
  if ! echo "$out" | grep -q "^\*" ; then
    echo "INFO: time is not synced, force it"
    echo "$out"
    sudo systemctl stop ntpd.service
    sudo ntpd -gq
    sudo systemctl start ntpd.service
  fi
}

if ps ax | grep -v grep | grep -q "bin/chronyd" ; then
  time_sync_func=chrony_sync
elif ps ax | grep -v grep | grep -q "bin/ntpd" ; then
  time_sync_func=ntp_sync
fi

if [ -z "$time_sync_func" ] ; then
  echo "ERROR: unknown time sync system"
  exit 1
fi

i=12
while ! $time_sync_func ; do
  if ! ((i=-1)) ; then
    echo "ERROR: time can not be synced. Exiting..."
    exit 1
  fi
  sleep 10
  echo "INFO: time can not be synced, retry $i"
done

echo "INFO: time is synced"
