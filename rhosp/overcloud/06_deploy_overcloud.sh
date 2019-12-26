#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

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

if [ -f $my_dir/../config/env.sh ]; then
   source $my_dir/../config/env.sh
else
   echo "File $my_dir/../config/env.sh not found"
   exit
fi


cd

if [[ "$SKIP_OVERCLOUD_NODE_INTROSPECTION" == false ]]; then
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
else
  export OVERCLOUD_ROLES="Controller Compute ContrailController"
  export Controller_hosts="${overcloud_cont_prov_ip}"
  export Compute_hosts="${overcloud_compute_prov_ip}"
  export ContrailController_hosts="${overcloud_ctrlcont_prov_ip}"
  nohup tripleo-heat-templates/deployed-server/scripts/get-occ-config.sh &

  openstack overcloud deploy --templates tripleo-heat-templates/ \
            --roles-file tripleo-heat-templates/roles_data_contrail_aio.yaml \
            --disable-validations \
            -e environment-rhel-registration.yaml \
            -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-net-single.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
            -e tripleo-heat-templates/environments/deployed-server-environment.yaml \
            -e tripleo-heat-templates/environments/deployed-server-bootstrap-environment-rhel.yaml \
            -e tripleo-heat-templates/environments/deployed-server-pacemaker-environment.yaml \
            -e misc_opts.yaml \
            -e contrail-parameters.yaml \
	    -e ctlplane-assignments.yaml \
            -e docker_registry.yaml
fi
