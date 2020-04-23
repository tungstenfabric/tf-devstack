#!/bin/bash

#All in one deployment
DEPLOY_COMPACT_AIO=${DEPLOY_COMPACT_AIO:-false}

#Assign floating ip address to undercloud node (disabled by default)
ASSIGN_FLOATING_IP=${ASSIGN_FLOATING_IP:-false}

workspace=${WORKSPACE:-$(pwd)}
vexxrc=${vexxrc:-"${workspace}/vexxrc"}

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -z ${OS_USERNAME+x}  && -z ${OS_PASSWORD+x} && -z ${OS_PROJECT_ID+x} ]]; then
   echo "Please export variables from VEXX openrc file first";
   echo Exiting
   exit 1
fi

# instances params
default_flavor=${vm_type:-'v2-standard-4'}
contrail_flavor='v2-standard-4'
disk_size_gb=100

#ssh options
SSH_USER=${SSH_USER:-'cloud-user'}
ssh_key_name=${ssh_key_name:-'worker'}
ssh_private_key=${ssh_private_key:-"~/.ssh/workers"}
ssh_opts="-i $ssh_private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# cluster options
rhosp_id=${rhosp_id:-${RANDOM}}
management_network_name=${management_network_name:-"rhosp13-mgmt"}
management_network_cidr=${management_network_cidr:-}
provision_network_name=${provision_network_name:-"rhosp13-prov"}
provision_network_cidr=${provision_network_cidr:-}
router_name=${router_name:-'router1'}
domain=${domain:-'vexxhost.local'}

# tags
PIPELINE_BUILD_TAG=${PIPELINE_BUILD_TAG:-}
SLAVE=${SLAVE:-}

net_tags=""
[ -n "$PIPELINE_BUILD_TAG" ] && net_tags+=" --tag PipelineBuildTag=${PIPELINE_BUILD_TAG}"
[ -n "$SLAVE" ] && net_tags+=" --tag SLAVE=${SLAVE}"

mgmt_net_cleanup=${mgmt_net_cleanup:-}
if ! openstack network show ${management_network_name} >/dev/null 2>&1 ; then
  [ -z "$mgmt_net_cleanup" ] && mgmt_net_cleanup=true
  management_network_cidr=${management_network_cidr:-'192.168.10.0/24'}
  echo "INFO: create network ${management_network_name}"
  openstack network create $net_tags ${management_network_name}
  echo "INFO: create subnet ${management_network_name} with cidr=$management_network_cidr"
  openstack subnet create $net_tags ${management_network_name} --network ${management_network_name} \
    --subnet-range $management_network_cidr
  echo "INFO: add subnet ${management_network_name} to ${router_name}"
  openstack router add subnet ${router_name} ${management_network_name}
else
  if [ -z "$management_network_cidr" ] ; then
    management_network_cidr=$(openstack subnet show ${management_network_name} -c cidr -f value)
    echo "INFO: detected management_network_cidr=$management_network_cidr"
  fi
fi

prov_net_cleanup=${prov_net_cleanup:-}
if ! openstack network show ${provision_network_name} >/dev/null 2>&1 ; then
  [ -z "$prov_net_cleanup" ] && prov_net_cleanup=true
  provision_network_cidr=${provision_network_cidr:-'192.168.20.0/24'}
  _prov_subnet=$(echo $provision_network_cidr | cut -d '/' -f1 | cut -d '.' -f1,2,3)
  _start="${_prov_subnet}.50"
  _end="${_prov_subnet}.70"
  echo "INFO: create network $provision_network_name"
  openstack network create $net_tags ${provision_network_name}
  echo "INFO: create subnet $provision_network_name with cidr=${provision_network_cidr} and allocation pool: $_start - $_end"
    openstack subnet create $net_tags ${provision_network_name} --network ${provision_network_name} \
      --subnet-range ${provision_network_cidr} --allocation-pool start=${_start},end=${_end} --gateway none
else
  if [ -z "$provision_network_cidr" ] ; then
    provision_network_cidr=$(openstack subnet show ${provision_network_name} -c cidr -f value)
    echo "INFO: detected provision_network_cidr=$provision_network_cidr"
  fi
fi

undercloud_instance="rhosp13-undercloud-${rhosp_id}"
#Get latest rhel image
image_name=$(openstack image list --status active -c Name -f value | grep "prepared-rhel7" | sort -nr | head -n 1)
image_id=$(openstack image show -c id -f value "$image_name")

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

#Assigning floating ip
if [[ "$ASSIGN_FLOATING_IP" == true ]]; then
    port_id=$(openstack port list --server ${undercloud_instance} --network ${management_network_name} -f value -c id)
    floating_ip_check=$(openstack floating ip list --port ${port_id} -f value -c ID)

    i="0"
    limit="10"
    while [[ "$floating_ip_check" == "" ]]; do
      i=$(( $i+1 ))
      echo Try $i out of $limit. floating_ip_check="$floating_ip_check"
      floating_ip=$(openstack floating ip create 0048fce6-c715-4106-a810-473620326cb0 -f value -c name)
      openstack server add floating ip ${undercloud_instance} $floating_ip
      floating_ip_check=$(openstack floating ip list --port ${port_id} -f value -c ID)
      sleep 3
      if (( $i > $limit)); then
        break
      fi
    done

    openstack server show ${undercloud_instance}

    floating_ip=$(openstack floating ip list --port ${port_id} -f value -c "Floating IP Address")
fi

overcloud_cont_instance="rhosp13-overcloud-cont-${rhosp_id}"
overcloud_compute_instance=
overcloud_ctrlcont_instance=
if $DEPLOY_COMPACT_AIO; then
  default_flavor=v2-standard-8
else
  overcloud_compute_instance="rhosp13-overcloud-compute-${rhosp_id}"
  overcloud_ctrlcont_instance="rhosp13-overcloud-ctrlcont-${rhosp_id}"
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

mgmt_subnet_gateway_ip=$(openstack subnet show ${management_network_name} -f value -c gateway_ip)
mgmt_subnet=$(echo $management_network_cidr | egrep -o '([0-9]{1,3}\.){2}[0-9]{1,3}')

prov_allocation_pool=$(openstack subnet show -f json -c allocation_pools $provision_network_name)
prov_end_addr=$(echo "$prov_allocation_pool" | jq -rc '.allocation_pools[0].end')
prov_subnet=$(echo $prov_end_addr | cut -d '.' -f1,2,3)
prov_inspection_iprange_start=$(echo $prov_end_addr | cut -d '.' -f 4)
if (( prov_inspection_iprange_start > 200 )) ; then
  echo "ERROR: prov_allocation_pool=$prov_allocation_pool"
  echo "ERROR: subnet must have at least 50 addresses avaialble in latest octet"
  exit 1
fi
(( prov_inspection_iprange_start+=1 ))
prov_inspection_iprange_end=$(( prov_inspection_iprange_start + 20 ))
prov_inspection_iprange="${prov_inspection_iprange_start},${prov_inspection_iprange_end}"
prov_dhcp_start=$(( prov_inspection_iprange_end + 1 ))
prov_dhcp_end=$(( prov_dhcp_start + 20 ))

undercloud_admin_host=$(( prov_dhcp_end + 1 ))
undercloud_public_host=$(( undercloud_admin_host + 1 ))

prov_subnet_len=$(echo ${provision_network_cidr} | cut -d '/' -f 2)
prov_ip_cidr=${undercloud_prov_ip}/$prov_subnet_len

overcloud_cont_ip=$(openstack server show ${overcloud_cont_instance} -f value -c addresses | cut -d '=' -f 2)
overcloud_compute_ip=
overcloud_ctrlcont_ip=
if ! $DEPLOY_COMPACT_AIO; then
  overcloud_compute_ip=$(openstack server show ${overcloud_compute_instance} -f value -c addresses | cut -d '=' -f 2)
  overcloud_ctrlcont_ip=$(openstack server show ${overcloud_ctrlcont_instance} -f value -c addresses | cut -d '=' -f 2)
fi

overcloud_fixed_vip=$overcloud_cont_ip
overcloud_fixed_controller_ip=$overcloud_cont_ip


if [[ "$ASSIGN_FLOATING_IP" == true ]]; then
    echo Undercloud is available by floating ip: $floating_ip
fi

# Copy ssh key to undercloud
rsync -a -e "ssh $ssh_opts" $ssh_private_key $SSH_USER@$undercloud_mgmt_ip:.ssh/id_rsa
ssh $ssh_opts $SSH_USER@$undercloud_mgmt_ip bash -c 'ssh-keygen -y -f .ssh/id_rsa >.ssh/id_rsa.pub ; chmod 600 .ssh/id_rsa*'

# Update vexxrc
echo
echo update vexxrc file $vexxrc
echo ==================================================================================
echo >> $vexxrc

echo export PROVIDER=$PROVIDER >> $vexxrc
echo export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION >> $vexxrc
echo export DEPLOY_COMPACT_AIO=$DEPLOY_COMPACT_AIO >> $vexxrc

echo export management_network_name=\"$management_network_name\" >> $vexxrc
echo export provision_network_name=\"$provision_network_name\" >> $vexxrc
echo export router_name=\"$router_name\" >> $vexxrc
echo export prov_net_cleanup=$prov_net_cleanup >> $vexxrc
echo export mgmt_net_cleanup=$mgmt_net_cleanup >> $vexxrc

echo export overcloud_virt_type=\"qemu\" >> $vexxrc
echo export domain=\"${domain}\" >> $vexxrc
echo export mgmt_subnet="\"${mgmt_subnet}"\" >> $vexxrc
echo export prov_subnet="\"${prov_subnet}"\" >> $vexxrc
echo export mgmt_gateway="\"${mgmt_subnet_gateway_ip}"\" >> $vexxrc
echo export mgmt_ip="\"${undercloud_mgmt_ip}"\" >> $vexxrc
echo export prov_ip="\"${undercloud_prov_ip}"\" >> $vexxrc
echo export undercloud_admin_host=\"${undercloud_admin_host}\" >> $vexxrc
echo export undercloud_public_host=\"${undercloud_public_host}\" >> $vexxrc

echo export fixed_vip="\"${overcloud_fixed_vip}"\" >> $vexxrc
echo export fixed_controller_ip="\"${overcloud_fixed_controller_ip}"\" >> $vexxrc

echo export prov_ip_cidr="\"${prov_ip_cidr}"\" >> $vexxrc
echo export prov_cidr="\"${provision_network_cidr}\"" >> $vexxrc
echo export prov_subnet_len="\"${prov_subnet_len}\"" >> $vexxrc
echo export prov_inspection_iprange=${prov_inspection_iprange}
echo export prov_dhcp_start=${prov_dhcp_start}
echo export prov_dhcp_end=${prov_dhcp_end}

if [[ "$ASSIGN_FLOATING_IP" == true ]]; then
    echo export floating_ip=\"${floating_ip}\" >> $vexxrc
fi

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
