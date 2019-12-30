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
    ["default"]="machines undercloud overcloud tf wait" \
    ["master"]="build machines undercloud overcloud tf wait" \
    ["platform"]="machines undercloud overcloud" \
)

# default env variables
export DEPLOYER='rhosp13'
# max wait in seconds after deployment
export WAIT_TIMEOUT=3600
#PROVIDER = [ kvm | vexx | aws ]
export PROVIDER=${PROVIDER:-'vexx'}

cd $my_dir

##### Assembling rhosp-environment.sh #####
if [[ ! -f ~/rhosp-environment.sh ]]; then
  cp -f $my_dir/config/env_${PROVIDER}.sh $my_dir/config/rhosp-environment.sh
  echo "export SKIP_OVERCLOUD_NODE_INTROSPECTION=true" >> $my_dir/config/rhosp-environment.sh

  if [ -f $my_dir/config/rhel-account.rc ]; then
     echo "Appending $my_dir/rhel-account.rc to rhosp-environment.sh"
     cat $my_dir/config/rhel-account.rc >> $my_dir/config/rhosp-environment.sh
  fi
  cp $my_dir/config/rhosp-environment.sh  ~/rhosp-environment.sh
fi
###########################################

source ~/rhosp-environment.sh

if [[ -z ${RHEL_USER+x}  && -z ${RHEL_PASSWORD+x} && -z ${RHEL_POOL_ID+x} ]]; then
   echo "Please put variables RHEL_USER, RHEL_PASSWORD and RHEL_POOL_ID into $my_dir/config/rhel-account.rc";
   echo Exiting
   exit 1
fi

source $my_dir/providers/kvm/virsh_functions

#ssh_opts="-i $ssh_private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"


function machines() {
  cd $my_dir
  #undercloud node provisioning
  if [[ `whoami` !=  'stack' ]]; then
    cat providers/common/add_user_stack.sh.template | envsubst > providers/common/add_user_stack.sh
    chmod 755 providers/common/add_user_stack.sh
    providers/common/add_user_stack.sh
    sudo mv ~/rhosp-environment.sh ~/tf-devstack ~/.tf /home/stack
    sudo chown -R stack:stack /home/stack/tf-devstack /home/stack/.tf /home/stack/rhosp-environment.sh
    echo Directory tf-devstack was moved to /home/stack. Please run next stages with user 'stack'
  fi
  sudo bash -c 'cd /home/stack/tf-devtsack/rhosp; ./undercloud/00_provision.sh'
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
     scp $ssh_opts providers/common/* overcloud/03_setup_predeployed_nodes.sh $SSH_USER@$ip:
     ssh $ssh_opts $SSH_USER@$ip ./add_user_stack.sh
     scp $ssh_opts ~/rhosp-environment.sh providers/common/* overcloud/03_setup_predeployed_nodes.sh stack@$ip:
     ssh $ssh_opts stack@$ip sudo ./03_setup_predeployed_nodes.sh &
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
