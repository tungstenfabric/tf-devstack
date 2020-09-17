#!/bin/bash -e

dnf update -y
dnf install -y --allowerasing chrony wget yum-utils vim iproute jq curl bind-utils network-scripts net-tools tmux createrepo bind-utils sshpass python36 python3-pip python3-virtualenv podman

echo "(allow svirt_tcg_t container_file_t ( dir ( read  )))"  >> /tmp/contrail_container.cil
sudo /sbin/semodule -i /tmp/contrail_container.cil
systemctl start chronyd
