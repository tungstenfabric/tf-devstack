#!/bin/bash -e

if ps ax | grep "bin/chronyd" | grep -v grep ; then
  echo "INFO: check sync with chronyd"
  i=12
  while ! chronyc -n sources | grep "^\^\*" ; do
    echo "INFO: time is not synced. force it ($i)"
    sudo systemctl stop chronyd.service
    for server in $(grep "^server " /etc/chrony.conf | awk '{print $2}') ; do
      sudo chronyd -q server $server iburst
    done
    sudo systemctl start chronyd.service
    sleep 10
    if ! ((i=-1)) ; then
      echo "ERROR: time can not be synced. Exiting..."
      exit 1
    fi
  done
elif ps ax | grep "bin/ntpd" | grep -v grep  ; then
  echo "INFO: check sync with ntpd"
  i=12
  while ! /usr/sbin/ntpq -n -c pe | grep "^\*" ; do
    echo "INFO: time is not synced. force it ($i)"
    sudo systemctl stop ntpd.service
    sudo ntpd -gq
    sudo systemctl start ntpd.service
    sleep 10
    if ! ((i=-1)) ; then
      echo "ERROR: time can not be synced. Exiting..."
      exit 1
    fi
  done
fi
