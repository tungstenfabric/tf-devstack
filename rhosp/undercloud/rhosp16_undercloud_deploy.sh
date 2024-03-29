

pkgs="python3-tripleoclient rhosp-director-images"
[[ -z "$overcloud_ceph_instance" ]] || pkgs+=" ceph-ansible"
if [[ "$USE_PREDEPLOYED_NODES" != 'true' && "${ENABLE_RHEL_REGISTRATION,,}" != 'true' ]] ; then
   pkgs+=" libguestfs-tools"
fi

# dont use on undercloud rhocp if any enabled (it might be enabled in case of operator nodes
# are prepared by rhosp)
sudo dnf install -y --disablerepo="rhocp-*" $pkgs

#RHEL8 undercloud install
if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]]; then
  export rhsm_image_registry_credentials="
  ContainerImageRegistryCredentials:
    ${OPENSTACK_CONTAINER_REGISTRY}:
      ${RHEL_USER}: '${RHEL_PASSWORD}'"
fi

if [[ -n "$overcloud_ceph_instance" ]] ; then
  tmpl=${RHOSP_MAJOR_VERSION}_containers-prepare-parameter-ceph.yaml.template
else
  tmpl=${RHOSP_MAJOR_VERSION}_containers-prepare-parameter.yaml.template
fi
cat $my_dir/$tmpl | envsubst >~/containers-prepare-parameter.yaml
echo "INFO: containers-prepare-parameter.yaml"
cat ~/containers-prepare-parameter.yaml

cat $my_dir/${RHOSP_MAJOR_VERSION}_undercloud.conf.template | envsubst >~/undercloud.conf
echo "INFO: undercloud.conf"
cat ~/undercloud.conf

cd
openstack undercloud install
