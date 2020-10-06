#!/bin/bash -e

#removing docker-ce package to avoid conflicts with podman
sudo dnf remove -y docker-ce-cli || true

if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
  # fix module otherwise upstream usage leads to packages conflicts
  sudo dnf module disable -y container-tools:rhel8
  sudo dnf module enable -y container-tools:2.0
  sudo dnf distro-sync -y 
fi

sudo dnf update -y
sudo dnf install -y --allowerasing chrony wget yum-utils vim iproute jq curl bind-utils network-scripts net-tools tmux createrepo bind-utils sshpass python36 python3-pip python3-virtualenv podman

sudo systemctl start chronyd
