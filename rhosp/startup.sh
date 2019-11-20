#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd $my_dir
#Checking RHEL registration file
if [ ! -f kvm-host/rhel-account.rc ]; then
   echo "File kvm-host/rhel-account.rc not found"
   exit
fi


#SKIP_KVM_PROVISIONING=${SKIP_KVM_PROVISIONING:-false}
SKIP_KVM_PROVISIONING=${SKIP_KVM_PROVISIONING:-true}
SKIP_CREATING_ENVIRONMENT=${SKIP_CREATING_ENVIRONMENT:-false}
SKIP_UNDERCLOUD=${SKIP_UNDERCLOUD:-false}
SKIP_OVERCLOUD=${SKIP_OVERCLOUD:-false}
SKIP_OVERCLOUD_NODE_INTROSPECTION=${SKIP_OVERCLOUD_NODE_INTROSPECTION:-false}

source $my_dir/kvm-host/env.sh
source $my_dir/kvm-host/virsh_functions

ssh_opts="-i $ssh_private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

#Build steps

#KVM part
cd $my_dir/kvm-host

if [[ "$SKIP_KVM_PROVISIONING" == false ]]; then
    sudo ./00_provision_kvm_host.sh
fi

if [[ "$SKIP_CREATING_ENVIRONMENT" == false ]]; then
    sudo ./01_create_env.sh
    wait_ssh ${mgmt_ip} ${ssh_private_key}
fi

if [[ "$SKIP_OVERCLOUD_NODE_INTROSPECTION" == false ]]; then
    sudo ./02_collecting_node_information.sh
else
    touch instackenv.json
fi



##################### Undercloud part ###########################

if [[ "$SKIP_UNDERCLOUD" == false ]]; then
   cd $my_dir
   scp -r $ssh_opts kvm-host/instackenv.json kvm-host/env.sh kvm-host/rhel-account.rc undercloud overcloud stack@${mgmt_ip}:
   ssh  $ssh_opts stack@${mgmt_ip} sudo ./undercloud/00_provision.sh
   ssh $ssh_opts stack@${mgmt_ip} sudo ./undercloud/01_deploy_as_root.sh
   ssh $ssh_opts stack@${mgmt_ip} ./undercloud/02_deploy_as_stack.sh
fi

##################### Overcloud part ###########################

if [[ "$SKIP_OVERCLOUD" == false ]]; then
   ssh  $ssh_opts stack@${mgmt_ip} ./overcloud/01_extract_overcloud_images.sh
   ssh  $ssh_opts stack@${mgmt_ip} ./overcloud/02_manage_overcloud_flavors.sh

   if [[ "$SKIP_OVERCLOUD_NODE_INTROSPECTION" == false ]]; then
      #Checking vbmc statuses and fix 'down'
      for vm in $(vbmc list -f value -c 'Domain name' -c Status | grep down | awk '{print $1}'); do
          vbmc start ${vm}
      done
      ssh  $ssh_opts stack@${mgmt_ip} ./overcloud/03_node_introspection.sh
   fi

   ssh  $ssh_opts stack@${mgmt_ip} ./overcloud/04_prepare_heat_templates.sh
   ssh  $ssh_opts stack@${mgmt_ip} sudo ./overcloud/05_prepare_containers.sh
   ssh  $ssh_opts stack@${mgmt_ip} ./overcloud/06_deploy_overcloud.sh
fi
