#!/bin/bash -e

sudo dnf update -y
sudo dnf install -y --allowerasing chrony wget yum-utils vim iproute jq curl bind-utils network-scripts net-tools tmux createrepo bind-utils sshpass python36 python3-pip python3-virtualenv podman

sudo systemctl start chronyd
