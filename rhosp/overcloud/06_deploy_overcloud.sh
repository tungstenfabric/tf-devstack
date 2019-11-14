#!/bin/bash

cd

if [[ `whoami` !=  'stack' ]]; then
   echo "This script must be run by user 'stack'"
   exit 1
fi


if [ -f ~/stackrc ]; then
   source ~/stackrc
else
   echo "File /home/stack/stackrc not found"
   exit
fi

cd
openstack overcloud deploy --templates tripleo-heat-templates/ \
          --roles-file tripleo-heat-templates/roles_data_contrail_aio.yaml \
          -e environment-rhel-registration.yaml \
          -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml \
          -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
          -e tripleo-heat-templates/environments/contrail/contrail-net-single.yaml \
          -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
          -e misc_opts.yaml \
          -e contrail-parameters.yaml \
          -e docker_registry.yaml

