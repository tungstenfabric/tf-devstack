#!/bin/bash


yum update -y
yum install -y  ntp wget yum-utils vim iproute jq curl bind-utils bridge-utils net-tools python-heat-agent*

chkconfig ntpd on
service ntpd start

# install pip for future run of OS checks
curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
python get-pip.py
pip install -q virtualenv docker

