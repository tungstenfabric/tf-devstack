tls_env_files=''
if [[ -n "$ENABLE_TLS" ]] ; then
  tls_env_files+=' -e tripleo-heat-templates/environments/contrail/contrail-tls.yaml'
  tls_env_files+=' -e tripleo-heat-templates/environments/ssl/tls-everywhere-endpoints-dns.yaml'
  tls_env_files+=' -e tripleo-heat-templates/environments/services/haproxy-public-tls-certmonger.yaml'
  tls_env_files+=' -e tripleo-heat-templates/environments/ssl/enable-internal-tls.yaml'
fi

rhel_reg_env_files=''
if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
  rhel_reg_env_files+=" -e tripleo-heat-templates/environments/rhsm.yaml"
  rhel_reg_env_files+=" -e rhsm.yaml"
fi

network_env_files=''
if [[ "$ENABLE_NETWORK_ISOLATION" == true ]] ; then
    network_env_files+=' -e tripleo-heat-templates/environments/network-isolation.yaml'
    network_env_files+=' -e tripleo-heat-templates/environments/contrail/contrail-net.yaml'
else
    network_env_files+=' -e tripleo-heat-templates/environments/contrail/contrail-net-single.yaml'
fi

if [[ "${DEPLOY_COMPACT_AIO,,}" == 'true' ]] ; then
  role_file="$(pwd)/tripleo-heat-templates/roles/ContrailAio.yaml"
else
  role_file="$(pwd)/tripleo-heat-templates/roles_data_contrail_aio.yaml"
fi

pre_deploy_nodes_env_files=''
if [[ "$USE_PREDEPLOYED_NODES" == true ]]; then
  pre_deploy_nodes_env_files+=" --disable-validations"
  pre_deploy_nodes_env_files+=" --deployed-server"
  pre_deploy_nodes_env_files+=" --overcloud-ssh-user $SSH_USER_OVERCLOUD"
  pre_deploy_nodes_env_files+=" --overcloud-ssh-key .ssh/id_rsa"
  pre_deploy_nodes_env_files+=" -e tripleo-heat-templates/environments/deployed-server-environment.yaml"
  pre_deploy_nodes_env_files+=" -e ctlplane-assignments.yaml"
  pre_deploy_nodes_env_files+=" -e hostname-map.yaml"

  if [[ "${DEPLOY_COMPACT_AIO,,}" == 'true' ]] ; then
    export OVERCLOUD_ROLES="ContrailAio"
    export ContrailAio_hosts="${overcloud_cont_prov_ip}"
  else
    export OVERCLOUD_ROLES="Controller Compute ContrailController"
    export Controller_hosts="${overcloud_cont_prov_ip}"
    export Compute_hosts="${overcloud_compute_prov_ip}"
    export ContrailController_hosts="${overcloud_ctrlcont_prov_ip}"
  fi
fi

./tripleo-heat-templates/tools/process-templates.py --clean \
  -r $role_file \
  -p tripleo-heat-templates/

./tripleo-heat-templates/tools/process-templates.py \
  -r $role_file \
  -p tripleo-heat-templates/

openstack overcloud deploy --templates tripleo-heat-templates/ \
  --stack overcloud --libvirt-type kvm \
  --roles-file $role_file \
  -e overcloud_containers.yaml \
  $rhel_reg_env_files \
  $pre_deploy_nodes_env_files \
  -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
  $network_env_files \
  -e tripleo-heat-templates/environments/contrail/endpoints-public-dns.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
  $tls_env_files \
  -e misc_opts.yaml \
  -e contrail-parameters.yaml \
  -e containers-prepare-parameter.yaml
