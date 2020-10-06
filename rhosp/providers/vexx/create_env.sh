#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

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
default_flavor=${vm_type:-'v2-standard-4'}
contrail_flavor='v2-standard-4'
disk_size_gb=100

#ssh options
SSH_USER=${SSH_USER:-'cloud-user'}
ssh_key_name=${ssh_key_name:-'worker'}
ssh_private_key=${ssh_private_key:-~/.ssh/workers}
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no"

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

domain=${domain:-'vexxhost.local'}

management_network_name=${management_network_name:-"management"}
management_network_cidr=$(openstack subnet show ${management_network_name} -c cidr -f value)
echo "INFO: detected management_network_cidr=$management_network_cidr"
if [[ -z "$management_network_cidr" ]] ; then
  echo "ERROR: failed to get management_network_cidr for the network $management_network_name"
  exit -1
fi

provision_network_name=${provision_network_name:-"data"}
provision_network_cidr=$(openstack subnet show ${provision_network_name} -c cidr -f value)
echo "INFO: detected provision_network_cidr=$provision_network_cidr"
if [[ -z "$provision_network_cidr" ]] ; then
  echo "ERROR: failed to get provision_network_cidr for the network $provision_network_name"
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

nova boot --flavor ${default_flavor} ${instance_tags} \
          --security-groups allow_all \
          --key-name=${ssh_key_name} \
          --nic net-name=${management_network_name} \
          --nic net-name=${provision_network_name} \
          --block-device source=image,id=${image_id},dest=volume,shutdown=remove,size=${disk_size_gb},bootindex=0 \
          --poll \
          ${undercloud_instance}

#Disabling port security on prov-network interface
openstack port list --server ${undercloud_instance} --network ${provision_network_name}
port_id=$(openstack port list --server ${undercloud_instance} --network ${provision_network_name} -f value -c id)
openstack port set --no-security-group --disable-port-security $port_id

overcloud_cont_instance="${RHOSP_VERSION}-overcloud-cont-${rhosp_id}"
overcloud_compute_instance=
overcloud_ctrlcont_instance=
if [[ "${DEPLOY_COMPACT_AIO,,}" == 'true' ]] ; then
  default_flavor=v2-standard-8
else
  overcloud_compute_instance="${RHOSP_VERSION}-overcloud-compute-${rhosp_id}"
  overcloud_ctrlcont_instance="${RHOSP_VERSION}-overcloud-ctrlcont-${rhosp_id}"
fi

#Creating overcloud nodes and disabling port security
for instance_name in ${overcloud_cont_instance} ${overcloud_compute_instance} ${overcloud_ctrlcont_instance}; do

  if [[ "${instance_name}" == "${overcloud_ctrlcont_instance}" ]]; then
    flavor=${contrail_flavor}
  else
    flavor=${default_flavor}
  fi

  nova boot --flavor ${flavor} --security-groups allow_all --key-name=${ssh_key_name} ${instance_tags} \
            --nic net-name=${provision_network_name} \
            --block-device source=image,id=${image_id},dest=volume,shutdown=remove,size=${disk_size_gb},bootindex=0 \
            --poll ${instance_name}
  port_id=$(openstack port list --server ${instance_name} --network ${provision_network_name} -f value -c id)
  openstack port set --no-security-group --disable-port-security ${port_id}
done

undercloud_ip_addresses=$(openstack server show ${undercloud_instance} -f value -c addresses)
undercloud_mgmt_ip=$(echo ${undercloud_ip_addresses} | egrep -o ${management_network_name}'=.[0-9.]*' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')
undercloud_prov_ip=$(echo ${undercloud_ip_addresses} | egrep -o ${provision_network_name}'=.[0-9.]*' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')

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

overcloud_fixed_vip="${prov_subnet}.$(( prov_inspection_iprange_end + 14 ))"

prov_subnet_len=$(echo ${provision_network_cidr} | cut -d '/' -f 2)
prov_ip_cidr=${undercloud_prov_ip}/$prov_subnet_len

overcloud_cont_ip=$(openstack server show ${overcloud_cont_instance} -f value -c addresses | cut -d '=' -f 2)
overcloud_compute_ip=
overcloud_ctrlcont_ip=
if [[ "${DEPLOY_COMPACT_AIO,,}" != 'true' ]] ; then
  overcloud_compute_ip=$(openstack server show ${overcloud_compute_instance} -f value -c addresses | cut -d '=' -f 2)
  overcloud_ctrlcont_ip=$(openstack server show ${overcloud_ctrlcont_instance} -f value -c addresses | cut -d '=' -f 2)
fi

wait_ssh ${undercloud_mgmt_ip} ${ssh_private_key}
prepare_rhosp_env_file $WORKSPACE/rhosp-environment.sh
tf_dir=$(readlink -e $my_dir/../../..)
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" \
  $WORKSPACE/rhosp-environment.sh $tf_dir $SSH_USER@$undercloud_mgmt_ip:

# Copy ssh key to undercloud
rsync -a -e "ssh -i $ssh_private_key $ssh_opts" $ssh_private_key $SSH_USER@$undercloud_mgmt_ip:.ssh/id_rsa
ssh $ssh_opts -i $ssh_private_key $SSH_USER@$undercloud_mgmt_ip 'ssh-keygen -y -f .ssh/id_rsa >.ssh/id_rsa.pub ; chmod 600 .ssh/id_rsa*'

# Update vexxrc
echo
echo update vexxrc file $vexxrc
echo ==================================================================================
echo >> $vexxrc

echo export PROVIDER=vexx >> $vexxrc

echo export overcloud_virt_type=\"qemu\" >> $vexxrc

echo export domain=\"${domain}\" >> $vexxrc

echo export undercloud_admin_host=\"${undercloud_admin_host}\" >> $vexxrc
echo export undercloud_public_host=\"${undercloud_public_host}\" >> $vexxrc

echo export fixed_vip="\"${overcloud_fixed_vip}"\" >> $vexxrc

echo export prov_ip="\"${undercloud_prov_ip}"\" >> $vexxrc
echo export prov_ip_cidr="\"${prov_ip_cidr}"\" >> $vexxrc
echo export prov_cidr="\"${provision_network_cidr}\"" >> $vexxrc
echo export prov_subnet_len="\"${prov_subnet_len}\"" >> $vexxrc
echo export prov_inspection_iprange=${prov_inspection_iprange} >> $vexxrc
echo export prov_dhcp_start=${prov_dhcp_start} >> $vexxrc
echo export prov_dhcp_end=${prov_dhcp_end} >> $vexxrc

echo export undercloud_instance=\"${undercloud_instance}\" >> $vexxrc
echo export overcloud_cont_instance=\"${overcloud_cont_instance}\" >> $vexxrc
echo export overcloud_compute_instance=\"${overcloud_compute_instance}\" >> $vexxrc
echo export overcloud_ctrlcont_instance=\"${overcloud_ctrlcont_instance}\" >> $vexxrc

echo export overcloud_cont_prov_ip=\""${overcloud_cont_ip}"\" >> $vexxrc
echo export overcloud_compute_prov_ip=\""${overcloud_compute_ip}"\" >> $vexxrc
echo export overcloud_ctrlcont_prov_ip=\""${overcloud_ctrlcont_ip}"\" >> $vexxrc

#Instance ip for sanity test
echo export instance_ip=\"${undercloud_mgmt_ip}\" >> $vexxrc

cat $vexxrc
