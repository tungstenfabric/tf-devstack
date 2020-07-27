#RHEL8 undercloud install
if [[ -n "$RHEL_USER" ]]; then
  export rhsm_image_registry_credentials="
  ContainerImageRegistryCredentials:
    ${OPENSTACK_CONTAINER_REGISTRY}:
      ${RHEL_USER}: '${RHEL_PASSWORD}'"
fi
cat containers-prepare-parameter.yaml.template | envsubst >~/containers-prepare-parameter.yaml
echo "INFO: containers-prepare-parameter.yaml"
cat ~/containers-prepare-parameter.yaml

cat ${RHEL_VERSION}_undercloud.conf.template | envsubst >~/undercloud.conf
echo "INFO: undercloud.conf"
cat ~/undercloud.conf

cd
openstack undercloud install
