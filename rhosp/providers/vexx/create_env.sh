#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/../../../common/common.sh"
source "$my_dir/../../../common/functions.sh"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

vexxrc=${vexxrc:-"${workspace}/vexxrc"}

if [[ -z ${OS_USERNAME+x}  && -z ${OS_PASSWORD+x} && -z ${OS_PROJECT_ID+x} ]]; then
  echo "Please export variables from VEXX openrc file first";
  echo Exiting
  exit 1
fi

if [[ "${USE_PREDEPLOYED_NODES,,}" != true ]]; then
  echo "ERROR: unsupported configuration for vexx: USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES"
  exit -1
fi

# instances params
domain=${domain:-'vexxhost.local'}
undercloud_flavor=${undercloud_flavor:-'v2-standard-4'}
overcloud_flavor=${overcloud_flavor:-'v2-standard-8'}
disk_size_gb=100

#ssh options
SSH_USER=${SSH_USER:-'cloud-user'}
ssh_key_name=${ssh_key_name:-'worker'}
ssh_private_key=${ssh_private_key:-~/.ssh/workers}

# lookup free name
while true ; do
  while true ; do
    rhosp_id=${RANDOM}
    if (( rhosp_id > 1000 )) ; then break ; fi
  done
  undercloud_instance="${RHOSP_VERSION}-undercloud-${rhosp_id}"
  if ! openstack server show $undercloud_instance >/dev/null 2>&1  ; then
    echo "INFO: free undercloud name undercloud_instance=${RHOSP_VERSION}-undercloud-${rhosp_id}"
    break
  fi
done
overcloud_cont_instance="${RHOSP_VERSION}-overcloud-cont-${rhosp_id}"
overcloud_compute_instance=
overcloud_ctrlcont_instance=
if [[ "${DEPLOY_COMPACT_AIO,,}" != 'true' ]] ; then
  overcloud_compute_instance="${RHOSP_VERSION}-overcloud-compute-${rhosp_id}"
  overcloud_ctrlcont_instance="${RHOSP_VERSION}-overcloud-ctrlcont-${rhosp_id}"
fi


management_network_name=${management_network_name:-"management"}
management_network_cidr=$(openstack subnet show ${management_network_name} -c cidr -f value)
echo "INFO: detected management_network_cidr=$management_network_cidr"
if [[ -z "$management_network_cidr" ]] ; then
  echo "ERROR: failed to get management_network_cidr for the network $management_network_name"
  exit -1
fi

provision_network_name=${provision_network_name:-"data"}
prov_cidr=$(openstack subnet show ${provision_network_name} -c cidr -f value)
echo "INFO: detected prov_cidr=$prov_cidr"
if [[ -z "$prov_cidr" ]] ; then
  echo "ERROR: failed to get prov_cidr for the network $provision_network_name"
  exit -1
fi

#Get latest rhel image
image_name=$(openstack image list --status active -c Name -f value | grep "prepared-${RHEL_VERSION}" | sort -nr | head -n 1)
image_id=$(openstack image show -c id -f value "$image_name")

# tags
PIPELINE_BUILD_TAG=${PIPELINE_BUILD_TAG:-}
SLAVE=${SLAVE:-}

instance_tags=""
[[ -n "$PIPELINE_BUILD_TAG" || -n "$SLAVE" ]] && instance_tags+=" --tags "
[ -n "$PIPELINE_BUILD_TAG" ] && instance_tags+="PipelineBuildTag=${PIPELINE_BUILD_TAG}"
[ -n "$PIPELINE_BUILD_TAG" ] && [ -n "$SLAVE" ] && instance_tags+=","
[ -n "$SLAVE" ] && instance_tags+="SLAVE=${SLAVE}"

# update before to create vms (in error case stackrc file needs have instances names for next cleanup)
echo "INFO: update vexxrc file $vexxrc"
cat <<EOF >> $vexxrc
# updated by tf-devstack
export PROVIDER="vexx"
export overcloud_virt_type="qemu"
export domain="${domain}"
export undercloud_instance="${undercloud_instance}"
export overcloud_cont_instance="${overcloud_cont_instance}"
export overcloud_compute_instance="${overcloud_compute_instance}"
export overcloud_ctrlcont_instance="${overcloud_ctrlcont_instance}"
EOF

function create_vm() {
  local name=$1
  local flavor=$2
  # networks list with security flag
  # e.g. management,data:insecure
  local networks=${3//,/ }
  local net_names="$(echo $networks | sed 's/:[a-zA-Z]*//g')"
  local net_opts=$(printf -- "--nic net-name=%s " $net_names)

  nova boot --security-groups allow_all \
            --flavor ${flavor} \
            --key-name=${ssh_key_name} \
            --block-device source=image,id=${image_id},dest=volume,shutdown=remove,size=${disk_size_gb},bootindex=0 \
            $net_opts \
            --poll ${instance_tags} ${name}
  local net
  local security
  for net in $networks ; do
    read net security <<< ${net//:/ }
    if [[ "$security" == 'insecure' ]] ; then
      local port_id=$(openstack port list --server ${name} --network ${net} -f value -c id)
      openstack port set --no-security-group --disable-port-security ${port_id}
    fi
  done
}

# Creating undercloud node
create_vm $undercloud_instance $undercloud_flavor "${management_network_name},${provision_network_name}:insecure"

# Creating overcloud nodes
for instance_name in ${overcloud_cont_instance} ${overcloud_compute_instance} ${overcloud_ctrlcont_instance}; do
  create_vm $instance_name $overcloud_flavor "${provision_network_name}:insecure"
done

function get_node_ip() {
  local ip=$(openstack server show $1 -f value -c addresses | tr ';' '\n' | grep "$2" | cut -d '=' -f 2)
  if [ -z "$ip" ] ; then
    echo "ERROR: failed to get ip for $1"
    exit -1
  fi
  if (( $(echo "$ip" | wc -l) != 1 )) ; then
    echo "ERROR: there are too many ips for $1 detected for network '$2': $ip"
    exit -1
  fi
  echo $ip
}

undercloud_mgmt_ip=$(get_node_ip $undercloud_instance $management_network_name)
prov_ip=$(get_node_ip $undercloud_instance $provision_network_name)

function get_overcloud_node_ip(){
  get_node_ip $1 $provision_network_name
}

overcloud_cont_prov_ip=$(get_overcloud_node_ip ${overcloud_cont_instance})
overcloud_compute_prov_ip=
overcloud_ctrlcont_prov_ip=
if [[ "${DEPLOY_COMPACT_AIO,,}" != 'true' ]] ; then
  overcloud_compute_prov_ip=$(get_overcloud_node_ip ${overcloud_compute_instance})
  overcloud_ctrlcont_prov_ip=$(get_overcloud_node_ip ${overcloud_ctrlcont_instance})
fi

prov_allocation_pool=$(openstack subnet show -f json -c allocation_pools $provision_network_name)
prov_end_addr=$(echo "$prov_allocation_pool" | jq -rc '.allocation_pools[0].end')

# randomize vips for ci
_octet3=$(echo $prov_end_addr | cut -d '.' -f 3)
if (( _octet3 < 255 )) ; then
  (( _octet3+= 1 ))
  _octet3=$(shuf -i${_octet3}-255 -n1)
  # whole octet4 is can used
  _octet4=$(shuf -i0-230 -n1)
else
  _octet4=$(echo $prov_end_addr | cut -d '.' -f 4)
  if (( _octet4 < 255 )) ; then
  (( _octet4+= 1 ))
    _octet4=$(shuf -i${_octet4}-255 -n1)
  fi
fi

prov_subnet="$(echo $prov_end_addr | cut -d '.' -f1,2).$_octet3"
prov_inspection_iprange_start=$_octet4
if (( prov_inspection_iprange_start > 229 )) ; then
  echo "ERROR: unsupported setup - prov_allocation_pool=$prov_allocation_pool"
  echo "ERROR: subnet must have at least 25 addresses avaialble in latest octet"
  exit 1
fi
(( prov_inspection_iprange_start+=1 ))
prov_inspection_iprange_end=$(( prov_inspection_iprange_start + 10 ))
prov_inspection_iprange="${prov_subnet}.${prov_inspection_iprange_start},${prov_subnet}.${prov_inspection_iprange_end}"
prov_dhcp_start="${prov_subnet}.$(( prov_inspection_iprange_end + 1 ))"
prov_dhcp_end="${prov_subnet}.$(( prov_inspection_iprange_end + 11 ))"

undercloud_admin_host="${prov_subnet}.$(( prov_inspection_iprange_end + 12 ))"
undercloud_public_host="${prov_subnet}.$(( prov_inspection_iprange_end + 13 ))"

fixed_vip="${prov_subnet}.$(( prov_inspection_iprange_end + 14 ))"

prov_subnet_len=$(echo ${prov_cidr} | cut -d '/' -f 2)
prov_ip_cidr=${prov_ip}/$prov_subnet_len

# wait undercloud node is ready
wait_ssh ${undercloud_mgmt_ip} ${ssh_private_key}
prepare_rhosp_env_file $WORKSPACE/rhosp-environment.sh
tf_dir=$(readlink -e $my_dir/../../..)
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" \
  $WORKSPACE/rhosp-environment.sh $tf_dir $SSH_USER@$undercloud_mgmt_ip:

# Copy ssh key to undercloud
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" $ssh_private_key $SSH_USER@$undercloud_mgmt_ip:.ssh/id_rsa
ssh $ssh_opts -i $ssh_private_key $SSH_USER@$undercloud_mgmt_ip 'ssh-keygen -y -f .ssh/id_rsa >.ssh/id_rsa.pub ; chmod 600 .ssh/id_rsa*'

# wait overcloud nodes are ready
function wait_overcloud_node() {
  local node=$1
  # use less timeout as undercloud is already waited and up
  local interval=3
  local max=10
  local silent_cmd=0
  wait_cmd_success "ssh $ssh_opts -i $ssh_private_key $SSH_USER@$undercloud_mgmt_ip ssh $ssh_opts $node uname -n" $interval $max $silent_cmd
}

jobs=""
for i in $overcloud_cont_prov_ip $overcloud_compute_prov_ip $overcloud_ctrlcont_prov_ip ; do
  wait_overcloud_node $i &
  jobs+=" $!"
done
for j in $jobs ; do
  wait $j
done

# Update vexxrc
echo
echo INFO: "update vexxrc file $vexxrc"
cat <<EOF >> $vexxrc
export instance_ip="${undercloud_mgmt_ip}"
export prov_ip="${prov_ip}"
export undercloud_admin_host="${undercloud_admin_host}"
export undercloud_public_host="${undercloud_public_host}"
export fixed_vip="${fixed_vip}"
export prov_ip_cidr="${prov_ip_cidr}"
export prov_cidr="${prov_cidr}"
export prov_subnet_len="${prov_subnet_len}"
export prov_inspection_iprange=${prov_inspection_iprange}
export prov_dhcp_start=${prov_dhcp_start}
export prov_dhcp_end=${prov_dhcp_end}
export overcloud_cont_prov_ip="${overcloud_cont_prov_ip}"
export overcloud_compute_prov_ip="${overcloud_compute_prov_ip}"
export overcloud_ctrlcont_prov_ip="${overcloud_ctrlcont_prov_ip}"
EOF

cat $vexxrc
