
#Creating environment-rhel-registration.yaml
cat $my_dir/environment-rhel-registration.yaml.template | envsubst > environment-rhel-registration.yaml

if [[ "$CONTRAIL_CONTAINER_TAG" =~ 'r1912' ]] ; then
  # Disable kernel vrouter hugepages for 1912
  sed -i '/ContrailVrouterHugepages/d' tripleo-heat-templates/environments/contrail/contrail-services.yaml
  cat <<EOF >> tripleo-heat-templates/environments/contrail/contrail-services.yaml
  ContrailVrouterHugepages1GB: '0'
  ContrailVrouterHugepages2MB: '128'
EOF

fi