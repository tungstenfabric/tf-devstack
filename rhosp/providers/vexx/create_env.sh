#!/bin/bash

if [[ -z ${OS_USERNAME+x}  && -z ${OS_PASSWORD+x} && -z ${OS_PROJECT_ID+x} ]]; then
   echo "Please export variables from VEXX openrc file first";
   echo Exiting
   exit 1
fi

#Using existing rhosp13-mgmt network
#openstack network create rhosp13-mgmt
#openstack subnet create rhosp13-test --network rhosp13-test --subnet-range 192.168.10.0/24
#openstack router add subnet router1 rhosp13-mgmt

openstack network create rhosp13-prov
openstack subnet create rhosp13-prov --network rhosp13-prov --subnet-range 192.168.12.0/24 --allocation-pool start=192.168.12.50,end=192.168.12.70 --gateway none

#Get latest rhel image
image_name=$(openstack image list  -f value -c Name | grep template-rhel-7 | tail -1)
image_id=$(openstack image list --name ${image_name} -f value -c ID)

nova boot --flavor v2-standard-4 \
          --security-groups allow_all \
          --key-name=gleb \
          --nic net-name=rhosp13-mgmt \
          --nic net-name=rhosp13-prov \
          --block-device source=image,id=${image_id},dest=volume,shutdown=remove,size=40,bootindex=0 \
          --poll \
          rhosp13-undercloud

#Disabling port security on prov-network interface
openstack port list --server rhosp13-undercloud --network rhosp13-prov
port_id=$(openstack port list --server rhosp13-undercloud --network rhosp13-prov -f value -c id)
openstack port set --no-security-group --disable-port-security $port_id

#Assigning floating ip
port_id=$(openstack port list --server rhosp13-undercloud --network rhosp13-mgmt -f value -c id)
floating_ip_check=$(openstack floating ip list --port ${port_id} -f value -c ID)

i="0"
limit="10"
while [[ "$floating_ip_check" == "" ]]; do
  i=$(( $i+1 ))
  echo Try $i out of $limit. floating_ip_check="$floating_ip_check"
  floating_ip=$(openstack floating ip create 0048fce6-c715-4106-a810-473620326cb0 -f value -c name)
  openstack server add floating ip rhosp13-undercloud $floating_ip
  floating_ip_check=$(openstack floating ip list --port ${port_id} -f value -c ID)
  sleep 3
  if (( $i > $limit)); then
    break
  fi
done

openstack server show rhosp13-undercloud

floating_ip=$(openstack floating ip list --port ${port_id} -f value -c "Floating IP Address")


#Creating overcloud nodes and disabling port security
for instance_name in rhosp13-overcloud-cont rhosp13-overcloud-compute rhosp13-overcloud-ctrlcont; do
    nova boot --flavor v2-standard-4 --security-groups allow_all --key-name=gleb \
              --nic net-name=rhosp13-prov \
              --block-device source=image,id=${image_id},dest=volume,shutdown=remove,size=30,bootindex=0 \
              --poll $instance_name
    port_id=$(openstack port list --server $instance_name --network rhosp13-prov -f value -c id)
    openstack port set --no-security-group --disable-port-security $port_id
done


mgmt_subnet=$(openstack subnet list --name rhosp13-mgmt -f value -c Subnet | egrep -o '([0-9]{1,3}\.){2}[0-9]{1,3}')
mgmt_subnet_gateway_ip=$(openstack subnet show rhosp13-mgmt -f value -c gateway_ip)
prov_subnet=$(openstack subnet list --name rhosp13-prov -f value -c Subnet | egrep -o '([0-9]{1,3}\.){2}[0-9]{1,3}')
undercloud_ip_addresses=$(openstack server show rhosp13-undercloud -f value -c addresses)
undercloud_mgmt_ip=$(echo ${undercloud_ip_addresses} | egrep -o 'rhosp13-mgmt=.[0-9.]*' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')
undercloud_prov_ip=$(echo ${undercloud_ip_addresses} | egrep -o 'rhosp13-prov=.[0-9.]*' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')

overcloud_cont_ip=$(openstack server show rhosp13-overcloud-cont -f value -c addresses | cut -d '=' -f 2)
overcloud_compute_ip=$(openstack server show rhosp13-overcloud-compute -f value -c addresses | cut -d '=' -f 2)
overcloud_ctrlcont_ip=$(openstack server show rhosp13-overcloud-ctrlcont -f value -c addresses | cut -d '=' -f 2)


echo Undercloud is available by floating ip: $floating_ip
echo
echo Please put following lines to your environment file tf-devstack/config/env_vexx.sh
echo ==================================================================================
echo export mgmt_subnet=\""${mgmt_subnet}"\"
echo export prov_subnet=\""${prov_subnet}"\"
echo export mgmt_gateway=\""${mgmt_subnet_gateway_ip}"\"
echo export mgmt_ip=\""${undercloud_mgmt_ip}"\"
echo export prov_ip=\""${undercloud_prov_ip}"\"
echo export fixed_vip=\""${prov_subnet}.200"\"
echo export fixed_controller_ip=\""${prov_subnet}.211"\"
echo export overcloud_cont_prov_ip=\""${overcloud_cont_ip}"\"
echo export overcloud_compute_prov_ip=\""${overcloud_compute_ip}"\"
echo export overcloud_ctrlcont_prov_ip=\""${overcloud_ctrlcont_ip}"\"


