#!/bin/bash

set -o errexit

function install_docker_centos() {
  yum install -y yum-utils device-mapper-persistent-data lvm2
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  unwanted_packages=(docker-ce docker-ce-cli containerd.io)
  for i in ${unwanted_packages[@]}; do
    rpm -e -v --noscripts ${i} || true
  done
  docker_packages=(docker-ce-${DOCKER_VERSION}* containerd.io)
  for i in ${docker_packages[@]}; do
    yum install -y ${i}
  done  
  systemctl stop firewalld || true
}

function install_required_packages_centos() {
  yum install -y python-setuptools iproute
  yum remove -y python-yaml
  yum remove -y python-requests
}

function set_default_k8s_version_centos() {
  default_k8s_version="1.12.3"
}