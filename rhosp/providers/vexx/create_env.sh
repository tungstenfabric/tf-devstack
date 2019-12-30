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

nova boot --flavor v2-standard-4 \
          --security-groups allow_all \
          --key-name=gleb \
          --nic net-name=rhosp13-mgmt \
          --nic net-name=rhosp13-prov \
          --block-device source=image,id=eb388da4-5445-4d24-8393-da12d6a18069,dest=volume,shutdown=remove,size=40,bootindex=0 \
          --poll \
          rhosp13-undercloud

#Creating and assigning floating IP address
floating_ip=$(openstack floating ip create 0048fce6-c715-4106-a810-473620326cb0 -f value -c name)
openstack server add floating ip rhosp13-undercloud  $floating_ip

openstack server show rhosp13-undercloud


#Disabling port security on prov-network interface
openstack port list --server rhosp13-undercloud --network rhosp13-prov
port_id=$(openstack port list --server rhosp13-undercloud --network rhosp13-prov -f value -c id)
openstack port set --no-security-group --disable-port-security $port_id


#Creating overcloud nodes and disabling port security
for instance_name in rhosp13-overcloud-cont rhosp13-overcloud-compute rhosp13-overcloud-ctrlcont; do
    nova boot --flavor v2-standard-4 --security-groups allow_all --key-name=gleb \
              --nic net-name=rhosp13-prov \
              --block-device source=image,id=899fbd42-8d8f-49e9-8013-56e9ea990fc1,dest=volume,shutdown=remove,size=30,bootindex=0 \
              --poll $instance_name
    port_id=$(openstack port list --server $instance_name --network rhosp13-prov -f value -c id)
    openstack port set --no-security-group --disable-port-security $port_id
done

undercloud_ip_addresses=$(openstack server show rhosp13-undercloud -f value -c addresses)
undercloud_mgmt_ip=$(echo ${undercloud_ip_addresses} | egrep -o 'rhosp13-mgmt=.*,' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')
undercloud_prov_ip=$(echo ${undercloud_ip_addresses} | egrep -o 'rhosp13-prov=.*,' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}')

overcloud_cont_ip=$(openstack server show rhosp13-overcloud-cont -f value -c addresses | cut -d '=' -f 2)
overcloud_compute_ip=$(openstack server show rhosp13-overcloud-compute -f value -c addresses | cut -d '=' -f 2)
overcloud_ctrlcont_ip=$(openstack server show rhosp13-overcloud-ctrlcont -f value -c addresses | cut -d '=' -f 2)


