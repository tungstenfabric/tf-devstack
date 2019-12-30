#!/bin/bash

if [[ -z ${OS_USERNAME+x}  && -z ${OS_PASSWORD+x} && -z ${OS_PROJECT_ID+x} ]]; then
   echo "Please export variables from VEXX openrc file first";
   echo Exiting
   exit 1
fi


floating_ip=$(openstack server show rhosp13-undercloud -f value -c addresses | awk '{print $3}')
openstack server remove floating ip rhosp13-undercloud $floating_ip

openstack server delete rhosp13-undercloud
openstack server delete rhosp13-overcloud-cont
openstack server delete rhosp13-overcloud-compute
openstack server delete rhosp13-overcloud-ctrlcont

openstack subnet delete rhosp13-prov
openstack network delete rhosp13-prov

#router_port=$(openstack port list --router router1 --network rhosp13-mgmt -f value -c id)
#openstack subnet delete rhosp13-mgmt
#openstack network delete rhosp13-mgmt

