#!/bin/bash

set -o errexit

source $TF_DEVSTACK_DIR/${distro}.sh

function get_ansible_deployer() {
  ANSIBLE_DIR=/root/contrail-ansible-deployer
  rm -rf $ANSIBLE_DIR

  if [ "$DEV_ENV" == "true" ]; then
    cd /root && git clone https://github.com/Juniper/contrail-ansible-deployer.git
  else
    ANSIBLE_TMP_DIR=/tmp/ansible_deployer
    # bug workaround: -v does not copy files from container folder to host folder
    # TODO add kolla
    docker run --rm -v /root/:$ANSIBLE_TMP_DIR --entrypoint "/usr/bin/cp" $CONTAINER_REGISTRY/contrail-kolla-ansible-deployer:$CONTRAIL_CONTAINER_TAG -r /root/contrail-ansible-deployer/ $ANSIBLE_TMP_DIR/
  fi
  cd $ANSIBLE_DIR
}

function install_docker() {
  if [[ $(docker version --format '{{.Server.Version}}' 2>&1) != ${DOCKER_VERSION}* ]]; then
      eval "install_docker_${distro}";
      systemctl daemon-reload
  fi
  systemctl start docker
}

function install_required_packages() {
  eval "install_required_packages_${distro}"
  easy_install pip
  pip install requests
  pip install pyyaml==3.13
  pip install 'ansible==2.7.11'
}

function prepare_ssh_key_authorization() {
  [ ! -d /root/.ssh ] && mkdir /root/.ssh && chmod 0700 /root/.ssh
  [ ! -f /root/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N ''
  [ ! -f /root/.ssh/authorized_keys ] && touch /root/.ssh/authorized_keys && chmod 0600 /root/.ssh/authorized_keys
  grep "$(</root/.ssh/id_rsa.pub)" /root/.ssh/authorized_keys -q || cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
}

function build_docker_images(){
  local dev_env_parent_dir=/root
  rm -rf "$dev_env_parent_dir"/tf-dev-env || true
  cd "$dev_env_parent_dir" && git clone https://github.com/tungstenfabric/tf-dev-env.git

  # build all
  cd "$dev_env_parent_dir"/tf-dev-env && AUTOBUILD=1 BUILD_DEV_ENV=1 ./startup.sh

  
  # fix env variables
  CONTAINER_REGISTRY="$(docker inspect --format '{{(index .IPAM.Config 0).Gateway}}' bridge):6666"
  CONTRAIL_CONTAINER_TAG="dev"
}

function set_default_k8s_version(){
  eval "set_default_k8s_version_${distro}"
}
