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
SKIP_OVERCLOUD_NODE_INTROSPECTION=${SKIP_OVERCLOUD_NODE_INTROSPECTION:-true}

cd $my_dir
#Checking RHEL registration file
if [ ! -f config/rhel-account.rc ]; then
   echo "File config/rhel-account.rc not found"
   exit
fi

if [[ $PROVIDER == 'vexx' ]]; then
   cp -f $my_dir/config/env_vexx.sh $my_dir/config/env.sh
fi

source $my_dir/config/env.sh
source $my_dir/providers/kvm/virsh_functions

#ssh_opts="-i $ssh_private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"


function machines() {
  cd $my_dir
  #undercloud node provisioning
  sudo undercloud/00_provision.sh
  cat providers/common/add_user_stack.sh.template | envsubst > providers/common/add_user_stack.sh
  chmod 755 providers/common/add_user_stack.sh
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
     scp $ssh_opts config/env.sh config/rhel-account.rc providers/common/* overcloud/03_setup_predeployed_nodes.sh stack@$ip:
     ssh $ssh_opts stack@$ip sudo ./03_setup_predeployed_nodes.sh &
  done
}

#Overcloud stage
function tf() {
   cd $my_dir
   SKIP_OVERCLOUD_NODE_INTROSPECTION=$SKIP_OVERCLOUD_NODE_INTROSPECTION ./overcloud/04_prepare_heat_templates.sh
   sudo ./overcloud/05_prepare_containers.sh
   SKIP_OVERCLOUD_NODE_INTROSPECTION=$SKIP_OVERCLOUD_NODE_INTROSPECTION ./overcloud/06_deploy_overcloud.sh
}


run_stages $STAGE
