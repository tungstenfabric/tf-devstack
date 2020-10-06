#!/bin/bash -e

sudo yum update -y
sudo yum install -y ntp wget yum-utils vim iproute jq curl bind-utils bridge-utils net-tools python-heat-agent*

sudo chkconfig ntpd on
sudo service ntpd start

# install pip for future run of OS checks
curl --retry 3 --retry-delay 10 https://bootstrap.pypa.io/get-pip.py | sudo python
sudo pip install -q virtualenv docker

# install pyton3 after pip
sudo yum install -y python3
curl --retry 3 --retry-delay 10 https://bootstrap.pypa.io/get-pip.py | sudo python3
sudo python3 -m pip install -q six pyyaml
