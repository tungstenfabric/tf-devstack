#!/bin/bash

dnf update -y
dnf install -y python3-tripleoclient chrony wget yum-utils vim iproute jq curl bind-utils bridge-utils net-tools tmux createrepo bind-utils sshpass python36 python3-pip python3-virtualenv podman

systemctl start chronyd

