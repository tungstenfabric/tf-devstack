#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/../../../common/common.sh"
source "$my_dir/../../../common/functions.sh"
source "$my_dir/../../../contrib/infra/kvm/functions.sh"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

if [[ "${USE_PREDEPLOYED_NODES,,}" == true ]]; then
  echo "ERROR: unsupported configuration for kvm: USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES"
  exit -1
fi

# SSH public key for user stack
export ssh_private_key=${ssh_private_key:-~/.ssh/id_rsa}
export ssh_public_key=${ssh_public_key:-~/.ssh/id_rsa.pub}

cd $WORKSPACE

export DEPLOY_POSTFIX=${DEPLOY_POSTFIX:-20}
export overcloud_cont_instance=$(make_instances_names "$OPENSTACK_CONTROLLER_NODES" "overcloud-cont")
export overcloud_ctrlcont_instance=""
if [ -z "$EXTERNAL_CONTROLLER_NODES" ] ; then
  overcloud_ctrlcont_instance=$(make_instances_names "$CONTROLLER_NODES" "overcloud-ctrlcont")
fi
if [ -z "$L3MH_CIDR" ] ; then
  export overcloud_compute_instance=$(make_instances_names "$AGENT_NODES" "overcloud-compute")
else
  export overcloud_compute_instance=$(make_instances_names "$AGENT_NODES" "overcloud-computel3mh")
fi

prepare_rhosp_env_file rhosp-environment.sh
sed 's/PROVIDER=.*/PROVIDER=bmc/g' rhosp-environment.sh > rhosp-environment-bmc.sh

$my_dir/01_create_env.sh
wait_ssh ${instance_ip} ${ssh_private_key}

$my_dir/02_collecting_node_information.sh

rsync -a -e "ssh -i $ssh_private_key $ssh_opts" ${ssh_private_key} ${ssh_public_key} root@${instance_ip}:./.ssh/
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" ${ssh_private_key} ${ssh_public_key} $SSH_USER@$instance_ip:./.ssh/

tf_dir=$(readlink -e $my_dir/../../..)
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" instackenv.json $tf_dir $SSH_USER@$instance_ip:
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment-bmc.sh $SSH_USER@$instance_ip:rhosp-environment.sh
if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
  wait_ssh ${ipa_mgmt_ip} ${ssh_private_key}
  rsync -a -e "ssh -i $ssh_private_key $ssh_opts" $tf_dir $SSH_USER@${ipa_mgmt_ip}:
  rsync -a -e "ssh -i $ssh_private_key $ssh_opts" rhosp-environment-bmc.sh $SSH_USER@${ipa_mgmt_ip}:rhosp-environment.sh
fi

function prepare_local_repo() {
  local instance_ip=$1
  local f="${RHEL_VERSION//\./}-tf-ci.repo"
  local ff="/tmp/$f"
  cat ${RHEL_VERSION//\./}-tf-ci.repo | envsubst > $ff
  rsync -a -e "ssh -i $ssh_private_key $ssh_opts" $ff $SSH_USER@$instance_ip:
  cat <<EOF | ssh $ssh_opts $SSH_USER@${instance_ip}
set -ex
sudo cp ~/$f /etc/yum.repos.d/
if [[ -n "$MIRROR_IP_ADDRESS" && -n "$MIRROR_FQDN" ]] ; then
  echo "$MIRROR_IP_ADDRESS  $MIRROR_FQDN" | sudo tee -a /etc/hosts
fi
sudo sed -i 's/enabled=1/enabled=0/g' /etc/yum/pluginconf.d/subscription-manager.conf
EOF
}

if [[ "$ENABLE_RHEL_REGISTRATION" != 'true' ]] ; then
  prepare_local_repo $instance_ip
  if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
    prepare_local_repo $ipa_mgmt_ip
  fi
fi
