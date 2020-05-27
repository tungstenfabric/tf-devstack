#!/bin/bash
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# Kubespray, when installing kubernetes version 1.16, installs docker-ce version 18.x.
# At some point, a problem arose: if you install docker-ce 18.x from the main repository,
# it installs docker-ce-cli 19.x as its dependency.
# In order to avoid this, before starting kubespray, we need to fix the version of docker-ce-cli.
# This function is called only when kubespray is installed.
function workaround_kubesray_docker_cli() {

  echo "docker cli workaround started"
  nodes="${CONTROLLER_NODES} ${AGENT_NODES}"
  nodes=`echo "${nodes}" | awk '$1=$1'`
  IFS=' '
  read -a iparr <<< "$nodes"
  echo "There are ${#iparr[*]} nodes in the cluster"

  for val in "${iparr[@]}";
  do
    userlink="$(whoami)@"
    userlink+="$val"
    echo $userlink
    echo ""
    if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
      ssh $userlink sudo yum install -y yum-utils yum-plugin-versionlock
      ssh $userlink sudo yum-config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo"
      ssh $userlink sudo yum versionlock "docker-ce-cli-18.09*"
      ssh $userlink sudo yum versionlock status
    elif [[ "$DISTRO" == "ubuntu" ]]; then
      sudo mv docker-ce-cli /etc/apt/preferences.d/
    fi
    echo ""
  done

  echo "docker cli workaround completed"

}
