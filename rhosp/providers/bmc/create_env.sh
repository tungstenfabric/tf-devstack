#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

if [[ "${USE_PREDEPLOYED_NODES,,}" == true ]]; then
  echo "ERROR: unsupported configuration for kvm: USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES"
  exit -1
fi

# env is created externally, just check availability
wait_ssh ${instance_ip} ${ssh_private_key}

cd $WORKSPACE
prepare_rhosp_env_file rhosp-environment.sh
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment.sh $my_dir/../../.. $SSH_USER@$instance_ip:

if [[ -n "$ENABLE_TLS" ]] ; then
  wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
  scp -r $ssh_opts rhosp-environment.sh $(dirname $my_dir) root@${ipa_mgmt_ip}:
  rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment.sh $my_dir/../../.. root@${ipa_mgmt_ip}:
fi
