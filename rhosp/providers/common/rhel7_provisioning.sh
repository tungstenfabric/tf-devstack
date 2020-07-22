#!/bin/bash -e

yum update -y
yum install -y ntp wget yum-utils vim iproute jq curl bind-utils bridge-utils net-tools python-heat-agent*

chkconfig ntpd on
service ntpd start

# install pip for future run of OS checks
curl --retry 3 --retry-delay 10 https://bootstrap.pypa.io/get-pip.py | python
pip install -q virtualenv docker

# install pyton3 after pip
yum install -y python3
curl --retry 3 --retry-delay 10 https://bootstrap.pypa.io/get-pip.py | python3
python3 -m pip install -q six pyyaml
