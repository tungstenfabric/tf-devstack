#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build machines undercloud overcloud tf wait logs" \
    ["default"]="machines undercloud overcloud tf" \
    ["master"]="build machines undercloud overcloud tf wait" \
    ["platform"]="machines undercloud overcloud" \
)

# default env variables
export DEPLOYER='rhosp'
# max wait in seconds after deployment
export WAIT_TIMEOUT=3600
#PROVIDER = [ kvm | vexx | aws ]
export PROVIDER=${PROVIDER:-'vexx'}
user=$(whoami)

cd $my_dir

##### Creating ~/rhosp-environment.sh #####
if [[ ! -f ~/rhosp-environment.sh ]]; then
  cp -f $my_dir/config/common.sh ~/rhosp-environment.sh
  cat $my_dir/config/env_${PROVIDER}.sh | grep '^export' >> ~/rhosp-environment.sh
  echo "export USE_PREDEPLOYED_NODES=true" >> ~/rhosp-environment.sh
fi

source ~/rhosp-environment.sh

if [[ -z ${RHEL_USER+x} ]]; then
  echo "Please enter you Red Hat Credentials. RHEL_USER="
  read -sr RHEL_USER_INPUT
  export RHEL_USER=$RHEL_USER_INPUT
  echo "export RHEL_USER=$RHEL_USER" >> ~/rhosp-environment.sh
fi

if [[ -z ${RHEL_PASSWORD+x} ]]; then
  echo "Please enter you Red Hat Credentials. RHEL_PASSWORD="
  read -sr RHEL_PASSWORD_INPUT
  export RHEL_PASSWORD=$RHEL_PASSWORD_INPUT
  echo "export RHEL_PASSWORD=$RHEL_PASSWORD" >> ~/rhosp-environment.sh
fi

#Put RHEL credentials into ~/rhosp-environment.sh
egrep -c '^export RHEL_USER=.+$' ~/rhosp-environment.sh || echo export RHEL_USER=\"$RHEL_USER\" >> ~/rhosp-environment.sh
egrep -c '^export RHEL_PASSWORD=.+$' ~/rhosp-environment.sh || echo export RHEL_PASSWORD=\"$RHEL_PASSWORD\" >> ~/rhosp-environment.sh

#source $my_dir/providers/kvm/virsh_functions

#ssh_opts="-i $ssh_private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"


function machines() {
  cd $my_dir
  sudo bash -c "source /home/$user/rhosp-environment.sh; $my_dir/undercloud/00_provision.sh"
}

function undercloud() {
  cd $my_dir
  sudo ./undercloud/01_deploy_as_root.sh
  ./undercloud/02_deploy_as_stack.sh
}

#Overcloud nodes provisioning
function overcloud() {
  cd $my_dir
  for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
     scp $ssh_opts ~/rhosp-environment.sh providers/common/* overcloud/03_setup_predeployed_nodes.sh $SSH_USER@$ip:
     #ssh $ssh_opts $SSH_USER@$ip ./add_user_stack.sh
     #scp $ssh_opts ~/rhosp-environment.sh providers/common/* overcloud/03_setup_predeployed_nodes.sh stack@$ip:
     ssh $ssh_opts $SSH_USER@$ip sudo ./03_setup_predeployed_nodes.sh &
  done
}

#Overcloud stage
function tf() {
   cd $my_dir
   ./overcloud/04_prepare_heat_templates.sh
   sudo ./overcloud/05_prepare_containers.sh
   ./overcloud/06_deploy_overcloud.sh
}


run_stages $STAGE
