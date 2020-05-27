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

  echo "INFO: docker cli workaround started"
  local nodes="${CONTROLLER_NODES} ${AGENT_NODES}"
  read -a iparr <<< "$nodes"
  echo "There are ${#iparr[*]} nodes in the cluster"

  if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
    for val in "${iparr[@]}";
    do
      local userlink="$(whoami)@"
      userlink+="$val"
      echo $userlink
      echo ""
    
      ssh $userlink sudo yum install -y yum-utils yum-plugin-versionlock
      ssh $userlink sudo yum-config-manager --add-repo ${DOCKER_REPO}
      ssh $userlink sudo yum versionlock ${DOCKER_CLI_VERSION_YUM}
      ssh $userlink sudo yum versionlock status
    
      echo ""
    done
  elif [[ "$DISTRO" == "ubuntu" ]]; then
     cat <<EOF > docker-ce-cli
	Package: docker-ce-cli
	Pin: version 5:18.09*
	Pin-Priority: 1001
	EOF
    sudo mv docker-ce-cli /etc/apt/preferences.d/
  fi

  echo "INFO: docker cli workaround completed"
  
}
