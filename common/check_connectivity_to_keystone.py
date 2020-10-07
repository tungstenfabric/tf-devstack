#!/usr/bin/env python3

import netaddr
import sys

vhost_cidr = sys.argv[1]
keystone_address = sys.argv[2]

net = netaddr.IPNetwork(vhost_cidr)
addr = netaddr.IPAddress(keystone_address)
cidr = net.cidr
if addr in cidr:
    print('True')
else:
    print('False')
