#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ ! -f ~/rhosp-environment.sh ]] ; then
   echo "File ~/rhosp-environment.sh not found"
   exit 1
fi

source ~/rhosp-environment.sh

cd
if [[ ! -f ./overcloud_containers.yaml || ! -f ./docker_registry.yaml ]] ; then
    error "ERROR: overcloud_containers.yaml or ./docker_registry.yaml are not found. Exit"
    exit 1
fi

openstack overcloud container image prepare \
  --namespace registry.access.redhat.com/rhosp13  --prefix=openstack- --tag-from-label {version}-{release} \
  --push-destination ${prov_ip}:8787 \
  --output-env-file ./docker_registry.yaml \
  --output-images-file ./overcloud_containers.yaml

echo 'openstack overcloud container image upload --config-file ./overcloud_containers.yaml'
openstack overcloud container image upload --config-file ./overcloud_containers.yaml
if [[ $? != 0 ]] ; then
    error "ERROR: 'openstack overcloud container image upload --config-file ./overcloud_containers.yaml' finished with error. Exit"
    exit 1
fi

./contrail-tripleo-heat-templates/tools/contrail/import_contrail_container.sh -f ./contrail_containers.yaml -r docker.io/tungstenfabric -t $CONTRAIL_CONTAINER_TAG

if [[ $? != 0 ]] ; then
    echo "ERROR: import_contrail_container.sh finished with error. Exit"
    exit 1
fi

sed -i ./contrail_containers.yaml -e "s/192.168.24.1/${prov_ip}/"
cat ./contrail_containers.yaml

echo 'openstack overcloud container image upload --config-file ./contrail_containers.yaml'
openstack overcloud container image upload --config-file ./contrail_containers.yaml
if [[ $? != 0 ]] ; then
    error "ERROR: 'openstack overcloud container image upload --config-file ./contrail_containers.yaml' finished with error. Exit"
    exit 1
fi

echo Checking catalog in docker registry
curl -X GET http://${prov_ip}:8787/v2/_catalog
