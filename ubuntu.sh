#!/bin/bash

set -o errexit

function install_docker_ubuntu() {
  apt install -y docker.io-${DOCKER_VERSION}*
}

function install_required_packages_ubuntu() {
  apt-get update
  apt-get install -y python-setuptools iproute
}

function set_default_k8s_version_ubuntu() {
  default_k8s_version="1.12.7"
}