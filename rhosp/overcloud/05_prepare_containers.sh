#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

if [ -f /home/stack/env_desc.sh ]; then
   source /home/stack/env_desc.sh
else
   echo "File /home/stack/env_desc.sh not found"
   exit    
fi


openstack overcloud container image prepare \
  --namespace registry.access.redhat.com/rhosp13  --prefix=openstack- --tag-from-label {version}-{release} \
  --push-destination ${prov_ip}:8787 \
  --output-env-file /home/stack/docker_registry.yaml \
  --output-images-file /home/stack/overcloud_containers.yaml

echo openstack overcloud container image upload --config-file /home/stack/overcloud_containers.yaml
openstack overcloud container image upload --config-file /home/stack/overcloud_containers.yaml

/home/stack/contrail-tripleo-heat-templates/tools/contrail/import_contrail_container.sh -f /home/stack/contrail_containers.yaml -r docker.io/tungstenfabric -t latest

sed -i /home/stack/contrail_containers.yaml -e 's/192.168.24.1/192.168.12.2/'

cat /home/stack/contrail_containers.yaml

echo openstack overcloud container image upload --config-file /home/stack/contrail_containers.yaml
openstack overcloud container image upload --config-file /home/stack/contrail_containers.yaml

echo Checking catalog in docker registry 
curl -X GET http://${prov_ip}:8787/v2/_catalog


