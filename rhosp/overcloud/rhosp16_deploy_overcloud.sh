
if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
   openstack overcloud deploy --templates tripleo-heat-templates/ \
             --stack overcloud --libvirt-type kvm \
             --roles-file tripleo-heat-templates/roles_data_contrail_aio.yaml \
             -e tripleo-heat-templates/environments/rhsm.yaml \
             -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
             -e tripleo-heat-templates/environments/contrail/contrail-net-single.yaml \
             -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
             -e misc_opts.yaml \
             -e contrail-parameters.yaml \
             -e containers-prepare-parameter.yaml \
             -e rhsm.yaml
else
   if [[ -z "${overcloud_compute_prov_ip}" ]]; then
      export OVERCLOUD_ROLES="ContrailAio"
      export ContrailAio_hosts="${overcloud_cont_prov_ip}"
   else
      export OVERCLOUD_ROLES="Controller Compute ContrailController"
      export Controller_hosts="${overcloud_cont_prov_ip}"
      export Compute_hosts="${overcloud_compute_prov_ip}"
      export ContrailController_hosts="${overcloud_ctrlcont_prov_ip}"
   fi
   nohup tripleo-heat-templates/deployed-server/scripts/get-occ-config.sh &
   job=$!
   openstack overcloud deploy --templates tripleo-heat-templates/ \
            --stack overcloud --libvirt-type kvm \
            --roles-file tripleo-heat-templates/roles_data_contrail_aio.yaml \
            --disable-validations \
            -e tripleo-heat-templates/environments/rhsm.yaml \
            -e tripleo-heat-templates/environments/deployed-server-environment.yaml \
            -e tripleo-heat-templates/environments/deployed-server-bootstrap-environment-rhel.yaml \
            -e tripleo-heat-templates/environments/deployed-server-pacemaker-environment.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-net-single.yaml \
            -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
            -e misc_opts.yaml \
            -e contrail-parameters.yaml \
            -e ctlplane-assignments.yaml \
            -e rhsm.yaml
   kill $job || true
fi
