#!/bin/bash

workspace=${WORKSPACE:-$(pwd)}
vexxrc=${vexxrc:-"${workspace}/vexxrc"}
source $vexxrc

if [[ -z ${OS_USERNAME+x}  && -z ${OS_PASSWORD+x} && -z ${OS_PROJECT_ID+x} ]]; then
   echo "Please export variables from VEXX openrc file first";
   echo Exiting
   exit 1
fi

if [[ -z ${undercloud_instance+x} && -z ${provision_network_name+x} ]]; then
   echo "Please export variables for cleanup first";
   echo Exiting
   exit 1
fi

if [[ -n ${floating_ip} ]]; then
    echo Removing floating ip ${floating_ip} from server ${undercloud_instance}
    openstack server remove floating ip ${undercloud_instance} ${floating_ip}
    openstack floating ip delete ${floating_ip}
fi

for i in ${overcloud_cont_instance} ${overcloud_ctrlcont_instance} ${overcloud_compute_instance} ${undercloud_instance} ; do
   echo Deleting server $i
   openstack server delete $i
done


