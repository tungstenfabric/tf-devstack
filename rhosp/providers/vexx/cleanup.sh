#!/bin/bash

if [[ -z ${OS_USERNAME+x}  && -z ${OS_PASSWORD+x} && -z ${OS_PROJECT_ID+x} ]]; then
   echo "Please export variables from VEXX openrc file first";
   echo Exiting
   exit 1
fi

if [[ -z ${undercloud_instance+x}  && -z ${floating_ip+x} && -z ${provider_network_name+x} ]]; then
   echo "Please export variables for cleanup first";
   echo Exiting
   exit 1
fi

echo Removing floating ip ${floating_ip} from server ${undercloud_instance}
openstack server remove floating ip ${undercloud_instance} ${floating_ip}

echo Deleting server ${undercloud_instance}
openstack server delete ${undercloud_instance}

echo Deleting server ${overcloud_cont_instance}
openstack server delete ${overcloud_cont_instance}

echo Deleting server ${overcloud_compute_instance}
openstack server delete ${overcloud_compute_instance}

echo Deleting server ${overcloud_ctrlcont_instance}
openstack server delete ${overcloud_ctrlcont_instance}

echo Deleting subnet ${provider_network_name}
openstack subnet delete ${provider_network_name}

echo Deleting network ${provider_network_name}
openstack network delete ${provider_network_name}

#router_port=$(openstack port list --router router1 --network rhosp13-mgmt -f value -c id)
#openstack subnet delete rhosp13-mgmt
#openstack network delete rhosp13-mgmt

