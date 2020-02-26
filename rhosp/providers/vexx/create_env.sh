#!/bin/bash


#Assign floating ip address to undercloud node (disabled by default)
ASSIGN_FLOATING_IP=${ASSIGN_FLOATING_IP:-false}

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -z ${OS_USERNAME+x}  && -z ${OS_PASSWORD+x} && -z ${OS_PROJECT_ID+x} ]]; then
   echo "Please export variables from VEXX openrc file first";
   echo Exiting
   exit 1
fi


default_flavor=${vm_type:-'v2-standard-4'}
#contrail_flavor='v2-highcpu-32'
contrail_flavor='v2-standard-4'
disk_size_gb=100
key_name=${key_name:-'worker'}
management_network_name="rhosp13-mgmt"
provider_network_base_name="rhosp13-prov"
domain="vexxhost.local"

#Using existing rhosp13-mgmt network
#openstack network create ${management_network_name}
#openstack subnet create ${management_network_name} --network ${management_network_name} --subnet-range 192.168.10.0/24
#openstack router add subnet router1 ${management_network_name}

prov_subnet_base_prefix='192.168'

for i in $(seq 12 50); do
  cidr="${prov_subnet_base_prefix}.$i.0/24"
  echo Checking $cidr
  subnet_check=$(openstack subnet list --subnet-range ${cidr} -f value -c ID)
  if [[ "$subnet_check" == "" ]]; then
     #Unique id for parallel deployments
     rhosp_id=$i
     provider_network_name="${provider_network_base_name}-$rhosp_id"
     _start=$"${prov_subnet_base_prefix}.$rhosp_id.50"
     _end=$"${prov_subnet_base_prefix}.$rhosp_id.70"
     echo subnet range $cidr is available. Creating
     openstack network create --tag "PipelineBuildTag=${PIPELINE_BUILD_TAG}" --tag "SLAVE=vexxhost" ${provider_network_name}
     openstack subnet create --tag "PipelineBuildTag=${PIPELINE_BUILD_TAG}" --tag "SLAVE=vexxhost" ${provider_network_name} --network ${provider_network_name} --subnet-range ${cidr} --allocation-pool start=${_start},end=${_end} --gateway none
     break;
  fi
done

undercloud_instance="rhosp13-undercloud-${rhosp_id}"
overcloud_cont_instance="rhosp13-overcloud-cont-${rhosp_id}"
overcloud_compute_instance="rhosp13-overcloud-compute-${rhosp_id}"
overcloud_ctrlcont_instance="rhosp13-overcloud-ctrlcont-${rhosp_id}"

#Get latest rhel image
image_name=$(openstack image list  -f value -c Name | grep template-rhel-7 | tail -1)
image_id=$(openstack image list --name ${image_name} -f value -c ID)


nova boot --flavor ${default_flavor} \
          --tags "PipelineBuildTag=${PIPELINE_BUILD_TAG},SLAVE=vexxhost" \
          --security-groups allow_all \
          --key-name=${key_name} \
          --nic net-name=${management_network_name} \
          --nic net-name=${provider_network_name} \
          --block-device source=image,id=${image_id},dest=volume,shutdown=remove,size=$disk_size_gb},bootindex=0 \
          --poll \
          ${undercloud_instance}

#Disabling port security on prov-network interface
openstack port list --server ${undercloud_instance} --network ${provider_network_name}
port_id=$(openstack port list --server ${undercloud_instance} --network ${provider_network_name} -f value -c id)
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

#Creating overcloud nodes and disabling port security
for instance_name in ${overcloud_cont_instance} ${overcloud_compute_instance} ${overcloud_ctrlcont_instance}; do

    if [[ "${instance_name}" == "${overcloud_ctrlcont_instance}" ]]; then
        flavor=${contrail_flavor}
    else
        flavor=${default_flavor}
    fi

    nova boot --flavor ${flavor} --security-groups allow_all --key-name=${key_name} \
              --tags "PipelineBuildTag=${PIPELINE_BUILD_TAG},SLAVE=vexxhost" \
              --nic net-name=${provider_network_name} \
              --block-device source=image,id=${image_id},dest=volume,shutdown=remove,size=${disk_size_gb},bootindex=0 \
              --poll ${instance_name}
    port_id=$(openstack port list --server ${instance_name} --network ${provider_network_name} -f value -c id)
    openstack port set --no-security-group --disable-port-security ${port_id}
done


mgmt_subnet=$(openstack subnet list --name ${management_network_name} -f value -c Subnet | egrep -o '([0-9]{1,3}\.){2}[0-9]{1,3}')
mgmt_subnet_gateway_ip=$(openstack subnet show ${management_network_name} -f value -c gateway_ip)
prov_subnet=$(openstack subnet list --name ${provider_network_name} -f value -c Subnet | egrep -o '([0-9]{1,3}\.){2}[0-9]{1,3}')
undercloud_ip_addresses=$(openstack server show ${undercloud_instance} -f value -c addresses)
undercloud_mgmt_ip=$(echo ${undercloud_ip_addresses} | egrep -o 'rhosp13-mgmt=.[0-9.]*' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')
undercloud_prov_ip=$(echo ${undercloud_ip_addresses} | egrep -o 'rhosp13-prov-[0-9]{2}=.[0-9.]*' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')

overcloud_cont_ip=$(openstack server show ${overcloud_cont_instance} -f value -c addresses | cut -d '=' -f 2)
overcloud_compute_ip=$(openstack server show ${overcloud_compute_instance} -f value -c addresses | cut -d '=' -f 2)
overcloud_ctrlcont_ip=$(openstack server show ${overcloud_ctrlcont_instance} -f value -c addresses | cut -d '=' -f 2)

vexxrc="${my_dir}/../../config/env_vexx.sh"

if [[ "$ASSIGN_FLOATING_IP" == true ]]; then
    echo Undercloud is available by floating ip: $floating_ip
fi
echo
echo file tf-devstack/config/env_vexx.sh was updated
echo ==================================================================================
echo >> $vexxrc

echo export domain=\"${domain}\" >> $vexxrc
echo export mgmt_subnet=\""${mgmt_subnet}"\" >> $vexxrc
echo export prov_subnet=\""${prov_subnet}"\" >> $vexxrc
echo export mgmt_gateway=\""${mgmt_subnet_gateway_ip}"\" >> $vexxrc
echo export mgmt_ip=\""${undercloud_mgmt_ip}"\" >> $vexxrc
echo export prov_ip=\""${undercloud_prov_ip}"\" >> $vexxrc
echo export fixed_vip=\""${prov_subnet}.200"\" >> $vexxrc
echo export fixed_controller_ip=\""${prov_subnet}.211"\" >> $vexxrc

if [[ "$ASSIGN_FLOATING_IP" == true ]]; then
    echo export floating_ip=\"${floating_ip}\" >> $vexxrc
fi
echo export provider_network_name=\"${provider_network_name}\" >> $vexxrc

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
