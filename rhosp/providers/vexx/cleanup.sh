
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
    echo "Removing floating ip ${floating_ip} from server ${undercloud_instance}"
    openstack server remove floating ip ${undercloud_instance} ${floating_ip} || true
    openstack floating ip delete ${floating_ip} || true
fi

for i in ${overcloud_cont_instance} ${overcloud_ctrlcont_instance} ${overcloud_compute_instance} ${undercloud_instance} ; do
   echo "Deleting server $i"
   openstack server delete $i || true
done

if [[ "$prov_net_cleanup" == 'true' ]] ; then
   echo "Deleting subnet ${provision_network_name}"
   openstack subnet delete ${provision_network_name} || true

   echo "Deleting network ${provision_network_name}"
   openstack network delete ${provision_network_name} || true
fi

if [[ "$mgmt_net_cleanup" == 'true' ]] ; then
   echo "Deleting subnet ${management_network_name}"
   openstack subnet delete $management_network_name || true
   echo "Deleting network ${management_network_name}"
   openstack network delete $management_network_name || true
fi
