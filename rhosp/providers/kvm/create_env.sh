#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

if [[ "${USE_PREDEPLOYED_NODES,,}" == true ]]; then
  echo "ERROR: unsupported configuration for kvm: USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES"
  exit -1
fi

cd $WORKSPACE
prepare_rhosp_env_file rhosp-environment.sh

$my_dir/01_create_env.sh
wait_ssh ${instance_ip} ${ssh_private_key}

$my_dir/02_collecting_node_information.sh

scp $ssh_opts ${ssh_private_key} ${ssh_public_key} root@${instance_ip}:./.ssh/
scp $ssh_opts ${ssh_private_key} ${ssh_public_key} $SSH_USER@${instance_ip}:./.ssh/
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment.sh $my_dir/../../.. $SSH_USER@$instance_ip:
ssh $ssh_opts $SSH_USER@${instance_ip} sed -i 's/PROVIDER=.*/PROVIDER=bmc/g' rhosp-environment.sh
if [[ -n "$ENABLE_TLS" ]] ; then
  wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
  rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment.sh $my_dir/../../.. root@${ipa_mgmt_ip}:
  ssh $ssh_opts root@${ipa_mgmt_ip} sed -i 's/PROVIDER=.*/PROVIDER=bmc/g' rhosp-environment.sh
fi
