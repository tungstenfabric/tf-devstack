#!/bin/bash

[[ "$DEBUG" == true ]] && set -x

function chrony_sync() {
  local out="$(chronyc -n sources)"
  if ! echo "$out" | grep -q "^\^\*" ; then
    echo "INFO: time is not synced, force it"
    sudo systemctl stop chronyd.service
    local cfg_file='/etc/chrony.conf'
    [ -e "$cfg_file" ] || cfg_file='/etc/chrony/chrony.conf'
    local server
    for server in $(grep "^server " $cfg_file | awk '{print $2}') ; do
      timeout 120 sudo chronyd -q server $server iburst
    done
    sudo systemctl start chronyd.service
    return 1
  fi
}

function ntp_query_state() {
  timeout 60 /usr/sbin/ntpq -n -c pe
}

function ntp_sync() {
  if ! ntp_query_state | grep -q "^\*" ; then
    echo "INFO: $(date): time is not synced, force it"
    timeout 60 sudo systemctl stop ntpd.service
    timeout 60 sudo ntpd -gq
    timeout 60 sudo systemctl start ntpd.service
    ntp_query_state | grep -q "^\*"
  fi
}

function chrony_show_time() {
  echo -e "INFO: $(date):\n$(timeout 120 chronyc -n sources)"
}

function ntp_show_time() {
  echo -e "INFO: $(date):\n$(ntp_query_state)"
}

if ps ax | grep -v grep | grep -q "bin/chronyd" ; then
  echo "INFO: $(date): ensure time is synced (chronyd)"
  time_sync_func=chrony_sync
  show_time=chrony_show_time
elif ps ax | grep -v grep | grep -q "bin/ntpd" ; then
  echo "INFO: $(date): ensure time is synced (ntpd)"
  timeout 60 sudo systemctl restart ntpd
  sleep 2
  time_sync_func=ntp_sync
  show_time=ntp_show_time
fi

if [ -z "$time_sync_func" ] ; then
  echo "ERROR: $(date): unknown time sync system"
  exit 1
fi

i=30
while ! $time_sync_func ; do
  if ! ((i-=1)) ; then
    echo "ERROR: $(date): time can not be synced. Exiting..."
    $show_time
    exit 1
  fi
  echo "INFO: $(date): time is not synced, retry $i in 20 sec"
  sleep 20
done

echo "INFO: $(date): time is synced"
