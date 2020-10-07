#!/bin/bash -ex
openstack overcloud container image prepare \
  --namespace ${OPENSTACK_CONTAINER_REGISTRY}/rhosp13  --prefix=openstack- --tag-from-label {version} \
  -e tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
  --set ceph_namespace=${OPENSTACK_CONTAINER_REGISTRY}/rhceph \
  --set ceph_image=rhceph-3-rhel7 \
  --set ceph_tag=3 \
  --push-destination ${prov_ip}:8787 \
  --output-env-file ./docker_registry.yaml \
  --output-images-file ./overcloud_containers.yaml \
  --tag '13.0'

echo 'openstack overcloud container image upload --config-file ./overcloud_containers.yaml'
openstack overcloud container image upload --config-file ./overcloud_containers.yaml

registry=${CONTAINER_REGISTRY:-'docker.io/tungstenfabric'}
contrail_tag=${CONTRAIL_CONTAINER_TAG:-'latest'}
./contrail-tripleo-heat-templates/tools/contrail/import_contrail_container.sh \
    -f ./contrail_containers.yaml -r $registry -t $contrail_tag

sed -i ./contrail_containers.yaml -e "s/192.168.24.1/${prov_ip}/"
cat ./contrail_containers.yaml

echo 'openstack overcloud container image upload --config-file ./contrail_containers.yaml'
openstack overcloud container image upload --config-file ./contrail_containers.yaml

echo Checking catalog in docker registry
curl -X GET http://${prov_ip}:8787/v2/_catalog
