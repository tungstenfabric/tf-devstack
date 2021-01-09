#!/bin/bash -eE
set -o pipefail

# NOTE: if you are planning to call this script several times different nodes' groups then please handle mac_octet in node's creation

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# NOTE: to let run this by user
export WORKSPACE=${WORKSPACE:-$HOME}
export JOB_NAME=${JOB_NAME:-'manual'}

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env" || /bin/true

# parameters for workers
VM_TYPE=${VM_TYPE:-'medium'}
NODES_COUNT=${NODES_COUNT:-1}

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
rm -f "$ENV_FILE"
touch "$ENV_FILE"
echo "export ENVIRONMENT_OS=${ENVIRONMENT_OS}" >> "$ENV_FILE"

OS_VARIANT="${OS_VARIANTS["${ENVIRONMENT_OS^^}"]}"
IMAGE="${OS_IMAGES["${ENVIRONMENT_OS^^}"]}"
echo "export IMAGE=$IMAGE" >> "$ENV_FILE"
IMAGE_SSH_USER=${OS_IMAGE_USERS["${ENVIRONMENT_OS^^}"]}
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$ENV_FILE"

INSTANCE_TYPE=${VM_TYPES[$VM_TYPE]}
if [[ -z "$INSTANCE_TYPE" ]]; then
  echo "ERROR: invalid VM_TYPE=$VM_TYPE"
  exit 1
fi
echo "INFO: VM_TYPE=$VM_TYPE  INSTANCE_TYPE='$INSTANCE_TYPE' (vcpus mem)"

# check previous env
for ((i=0; i<${NODES_COUNT}; ++i)); do
  assert_env_exists "${VM_NAME}_$i"
done

# check image
if ! virsh vol-info --pool $BASE_IMAGE_POOL $IMAGE ; then
  echo "ERROR: image $IMAGE could not be found. please create it with prepare_image.sh script"
  exit 1
fi

# check and create network
# just one network for all for now
net_name=${KVM_NETWORK}_1
if ! virsh net-list | grep -q $net_name ; then
  create_network_dhcp $net_name 10.100.0.1
fi

# create pool
create_pool $POOL_NAME

# TODO: think about adding tags: JOB_TAG, GROUP_TAG to be able to clean up smartly
#instance_name="${PREFIX}${BUILD_TAG}"
#job_tag="JobTag=${BUILD_TAG}"
#group_tag="GroupTag=${PREFIX}${BUILD_TAG}"

# create VM-s
ids=''
for ((i=0; i<${NODES_COUNT}; ++i)); do
  vm_name=''
  if [[ -n "$WORKER_NAME_PREFIX" ]]; then
    vm_name="${WORKER_NAME_PREFIX}_"
  fi
  vm_name+="${BASE_VM_NAME}_$i"
  create_vm $vm_name $INSTANCE_TYPE $net_name $IMAGE $OS_VARIANT "0$i"
  ids+=" $vm_name"
done

# TODO: fix waiting in case when several setups uses the same network
wait_dhcp $net_name $NODES_COUNT
ips=''
for (( i=0; i<${NODES_COUNT}; ++i )); do
  ip=`get_ip_by_mac $net_name 52:54:00:00:10:0$i`
  echo "INFO: node #$i, IP $ip (network $net_name)"
  ips+=" $ip"
done

hosts=''
for ip in $ips ; do
  hname="node-$(echo $ip | tr '.' '-')"
  hosts+=$(printf "$ip  ${hname}.${DOMAIN}  ${hname}\n")
done

ssh_config=$(printf "Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile=/dev/null")

id_rsa="$(cat $HOME/.ssh/id_rsa)"
id_rsa_pub="$(cat $HOME/.ssh/id_rsa.pub)"
for ip in ${ips[@]} ; do
  wait_ssh $ip
  attach_opt_vols $ip
  cat <<EOF | ssh $SSH_OPTS root@${ip}
hname="node-\$(echo $ip | tr '.' '-')"
echo \$hname > /etc/hostname
hostname \$hname
domainname ${DOMAIN}
echo "$hosts" >> /etc/hosts
echo "$ssh_config" > /root/.ssh/config
echo "$id_rsa" > /root/.ssh/id_rsa
echo "$id_rsa_pub" > /root/.ssh/id_rsa.pub
echo "$id_rsa_pub" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/id_rsa /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
if [[ "$IMAGE_SSH_USER" != 'root' ]] ; then
  echo "$ssh_config" > /home/$IMAGE_SSH_USER/.ssh/config
  echo "$id_rsa" > /home/$IMAGE_SSH_USER/.ssh/id_rsa
  echo "$id_rsa_pub" > /home/$IMAGE_SSH_USER/.ssh/id_rsa.pub
  echo "$id_rsa_pub" > /home/$IMAGE_SSH_USER/.ssh/authorized_keys
  chmod 600 /home/$IMAGE_SSH_USER/.ssh/id_rsa /home/$IMAGE_SSH_USER/.ssh/id_rsa.pub /home/$IMAGE_SSH_USER/.ssh/authorized_keys
  chown $IMAGE_SSH_USER /home/$IMAGE_SSH_USER/.ssh/id_rsa /home/$IMAGE_SSH_USER/.ssh/id_rsa.pub /home/$IMAGE_SSH_USER/.ssh/authorized_keys
fi
EOF

done

# TODO: add next section
#image_up_script=${OS_IMAGES_UP["${ENVIRONMENT_OS^^}"]}
#if [[ -n "$image_up_script" && -e ${my_dir}/../hooks/${image_up_script}/up.sh ]] ; then
#  ${my_dir}/../hooks/${image_up_script}/up.sh
#fi

ids="$(echo $ids | sed 's/ /,/g')"
echo "export INSTANCE_IDS=$ids" >> "$ENV_FILE"
ips="$(echo $ips | sed 's/ /,/g')"
echo "export INSTANCE_IPS=$ips" >> "$ENV_FILE"
instance_ip=`echo $ips | cut -d',' -f1`
echo "export instance_ip=$instance_ip" >> "$ENV_FILE"
