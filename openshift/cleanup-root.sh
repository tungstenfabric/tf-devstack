#!/bin/bash

set -x

# down vhost0 and unload kernel module
ifdown vhost0

# remove contrail files from host
rm -rf  /tmp/* \
        /var/lib/contrail \
        /var/contrail \
        /var/log/contrail \
        /etc/sysconfig/network-scripts/*vhost* \
        /etc/sysconfig/network-scripts/*vrouter*

# restore resolv.conf and restart network related services
[ -f /etc/resolv.conf.org ] && mv /etc/resolv.conf.org /etc/resolv.conf || {
  [ -f /etc/resolv.conf.org.bkp ] && cp -f /etc/resolv.conf.org.bkp /etc/resolv.conf
}
service dnsmasq restart
service NetworkManager restart
service iptables restart
