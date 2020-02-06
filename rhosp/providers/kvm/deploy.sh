#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# default env variables
#PROVIDER = [ kvm | vexx | aws ]
export PROVIDER=${PROVIDER:-'kvm'}

cd $my_dir
#Checking RHEL registration file
if [ ! -f config/rhel-account.rc ]; then
   echo "File config/rhel-account.rc not found"
   exit
fi


#SKIP_KVM_PROVISIONING=${SKIP_KVM_PROVISIONING:-false}
SKIP_KVM_PROVISIONING=${SKIP_KVM_PROVISIONING:-true}
SKIP_CREATING_ENVIRONMENT=${SKIP_CREATING_ENVIRONMENT:-false}
SKIP_UNDERCLOUD=${SKIP_UNDERCLOUD:-false}
SKIP_OVERCLOUD=${SKIP_OVERCLOUD:-false}
SKIP_OVERCLOUD_NODE_INTROSPECTION=${SKIP_OVERCLOUD_NODE_INTROSPECTION:-false}

source $my_dir/config/env.sh
source $my_dir/providers/kvm/virsh_functions

ssh_opts="-i $ssh_private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

#Build steps

#KVM part
cd $my_dir/providers/kvm

if [[ "$SKIP_KVM_PROVISIONING" == false ]]; then
    sudo ./00_provision_kvm_host.sh
fi

if [[ "$SKIP_CREATING_ENVIRONMENT" == false ]]; then
    sudo SKIP_OVERCLOUD_NODE_INTROSPECTION=${SKIP_OVERCLOUD_NODE_INTROSPECTION} ./01_create_env.sh
    wait_ssh ${mgmt_ip} ${ssh_private_key}
fi

if [[ "$SKIP_OVERCLOUD_NODE_INTROSPECTION" == false ]]; then
    sudo ./02_collecting_node_information.sh
else
    sudo touch instackenv.json	
fi


cd $my_dir

##################### Undercloud part ###########################

if [[ "$SKIP_UNDERCLOUD" == false ]]; then
   scp -r $ssh_opts providers/kvm/instackenv.json config/env.sh config/rhel-account.rc undercloud overcloud stack@${mgmt_ip}:
   ssh  $ssh_opts stack@${mgmt_ip} sudo ./undercloud/00_provision.sh
   ssh $ssh_opts stack@${mgmt_ip} sudo ./undercloud/01_deploy_as_root.sh
   ssh $ssh_opts stack@${mgmt_ip} ./undercloud/02_deploy_as_stack.sh
fi

##################### Overcloud part ###########################

if [[ "$SKIP_OVERCLOUD" == false ]]; then
   	
   ssh  $ssh_opts stack@${mgmt_ip} ./overcloud/02_manage_overcloud_flavors.sh

   if [[ "$SKIP_OVERCLOUD_NODE_INTROSPECTION" == false ]]; then
      ssh  $ssh_opts stack@${mgmt_ip} ./overcloud/01_extract_overcloud_images.sh
      #Checking vbmc statuses and fix 'down'
      for vm in $(vbmc list -f value -c 'Domain name' -c Status | grep down | awk '{print $1}'); do
          vbmc start ${vm}
      done
      ssh  $ssh_opts stack@${mgmt_ip} ./overcloud/03_node_introspection.sh
   else
      #Copying keypair to the undercloud
      scp $ssh_opts $ssh_private_key $ssh_public_key stack@${mgmt_ip}:.ssh/
      #start overcloud VMs
      for domain in $(virsh list --name --all | grep rhosp13-overcloud); do virsh start $domain; done

      for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
          wait_ssh ${ip} ${ssh_private_key}
          scp $ssh_opts config/rhel-account.rc config/env.sh overcloud/03_setup_predeployed_nodes.sh stack@$ip:
      done

      #parallel ssh
      jobs=''
      res=0
      for ip in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip; do
	  ssh $ssh_opts stack@${ip} sudo ./03_setup_predeployed_nodes.sh &
	  jobs+=" $!"
      done
      echo Parallel pre-instatallation overcloud nodes. pids: $jobs. Waiting...
      for i in $jobs ; do
        wait $i || res=1
      done
      if [[ "${res}" == 1 ]]; then
	 echo errors appeared during overcloud nodes pre-installation. Exiting
         exit 1
      fi

   fi

   ssh $ssh_opts stack@${mgmt_ip} SKIP_OVERCLOUD_NODE_INTROSPECTION=$SKIP_OVERCLOUD_NODE_INTROSPECTION ./overcloud/04_prepare_heat_templates.sh
   ssh $ssh_opts stack@${mgmt_ip} sudo ./overcloud/05_prepare_containers.sh
   ssh $ssh_opts stack@${mgmt_ip} SKIP_OVERCLOUD_NODE_INTROSPECTION=$SKIP_OVERCLOUD_NODE_INTROSPECTION ./overcloud/06_deploy_overcloud.sh
fi
