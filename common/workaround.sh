#!/bin/bash
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# Kubespray, when installing kubernetes version 1.16, installs docker-ce version 18.x.
# At some point, a problem arose: if you install docker-ce 18.x from the main repository,
# it installs docker-ce-cli 19.x as its dependency.
# In order to avoid this, before starting kubespray, we need to fix the version of docker-ce-cli.
# This function is called only when kubespray is installed.
function workaround_kubesray_docker_cli() {
  DOCKER_CLI_VERSION_YUM=${DOCKER_CLI_VERSION:="docker-ce-cli-18.09*"}
  DOCKER_REPO=${DOCKER_REPO:="https://download.docker.com/linux/centos/docker-ce.repo"}

  if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
    sudo yum install -y yum-utils yum-plugin-versionlock
    sudo yum-config-manager --add-repo ${DOCKER_REPO}
    sudo yum versionlock ${DOCKER_CLI_VERSION_YUM}
  fi
}