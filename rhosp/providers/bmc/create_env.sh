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

cd $WORKSPACE
prepare_rhosp_env_file rhosp-environment.sh
tf_dir=$(readlink -e $my_dir/../../..)

function _prep_machine() {
  local addr=$1
  wait_ssh ${addr} ${ssh_private_key}
  rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment.sh $tf_dir $SSH_USER@$addr:
  rsync -a -e "ssh -i $ssh_private_key $ssh_opts" $ssh_private_key $SSH_USER@$addr:.ssh/id_rsa
  eval "ssh $ssh_opts -i $ssh_private_key $SSH_USER@$addr 'ssh-keygen -y -f .ssh/id_rsa >.ssh/id_rsa.pub ; chmod 600 .ssh/id_rsa*'"
}

_prep_machine $instance_ip

if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
  _prep_machine $ipa_mgmt_ip
fi
