
if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
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
   if [[ -z "${overcloud_compute_prov_ip}" ]]; then
      role_file="tripleo-heat-templates/roles/ContrailAio.yaml"
      export OVERCLOUD_ROLES="ContrailAio"
      export ContrailAio_hosts="${overcloud_cont_prov_ip}"
   else
      role_file="tripleo-heat-templates/roles_data_contrail_aio.yaml"
      export OVERCLOUD_ROLES="Controller Compute ContrailController"
      export Controller_hosts="${overcloud_cont_prov_ip}"
      export Compute_hosts="${overcloud_compute_prov_ip}"
      export ContrailController_hosts="${overcloud_ctrlcont_prov_ip}"
   fi
   nohup tripleo-heat-templates/deployed-server/scripts/get-occ-config.sh &
   job=$!
   openstack overcloud deploy --templates tripleo-heat-templates/ \
            --roles-file $role_file \
            --disable-validations \
            -e environment-rhel-registration.yaml \
            -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml \
            -e tripleo-heat-templates/environments/deployed-server-environment.yaml \
            -e tripleo-heat-templates/environments/deployed-server-bootstrap-environment-rhel.yaml \
            -e tripleo-heat-templates/environments/deployed-server-pacemaker-environment.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-net-single.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
            -e misc_opts.yaml \
            -e contrail-parameters.yaml \
            -e ctlplane-assignments.yaml \
            -e docker_registry.yaml
   kill $job || true
fi
