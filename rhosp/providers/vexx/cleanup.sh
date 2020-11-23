
if [[ -z ${OS_USERNAME+x}  && -z ${OS_PASSWORD+x} && -z ${OS_PROJECT_ID+x} ]]; then
   echo "Please export variables from VEXX openrc file first";
   echo Exiting
   exit 1
fi

for instance_name in ${overcloud_cont_instance//,/ } ${overcloud_compute_instance//,/ } ${overcloud_ctrlcont_instance//,/ } ${undercloud_instance}; do
   echo "Deleting server $instance_name"
   openstack server delete $instance_name || true
done
