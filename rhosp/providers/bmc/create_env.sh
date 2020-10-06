#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/../../../common/common.sh"
source "$my_dir/../../../common/functions.sh"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

if [[ "${USE_PREDEPLOYED_NODES,,}" == true ]]; then
  echo "ERROR: unsupported configuration for kvm: USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES"
  exit -1
fi

# SSH public key for user stack
export ssh_private_key=${ssh_private_key:-~/.ssh/workers}

if [ -n "$SSH_EXTRA_OPTIONS" ] ; then
  # add extra options for create_env.
  # for bmc setup it is needed for ssh proxy settings
  export ssh_opts="$ssh_opts $SSH_EXTRA_OPTIONS"
fi

# env is created externally, just check availability
wait_ssh ${instance_ip} ${ssh_private_key}

cd $WORKSPACE
prepare_rhosp_env_file rhosp-environment.sh
tf_dir=$(readlink -e $my_dir/../../..)
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment.sh $tf_dir $SSH_USER@$instance_ip:

if [[ -n "$ENABLE_TLS" ]] ; then
  wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
  rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment.sh $tf_dir root@${ipa_mgmt_ip}:
fi
