

pkgs="python3-tripleoclient rhosp-director-images rhosp-director-images-ipa"
[[ -z "$overcloud_ceph_instance" ]] || pkgs+=" ceph-ansible"
sudo dnf install -y $pkgs

#RHEL8 undercloud install
if [[ -n "$RHEL_USER" ]]; then
  export rhsm_image_registry_credentials="
  ContainerImageRegistryCredentials:
    ${OPENSTACK_CONTAINER_REGISTRY}:
      ${RHEL_USER}: '${RHEL_PASSWORD}'"
fi

if [[ -n "$overcloud_ceph_instance" ]] ; then
  tmpl=containers-prepare-parameter-ceph.yaml.template
else
  tmpl=containers-prepare-parameter.yaml.template
fi
cat $my_dir/$tmpl | envsubst >~/containers-prepare-parameter.yaml
echo "INFO: containers-prepare-parameter.yaml"
cat ~/containers-prepare-parameter.yaml

cat $my_dir/${RHOSP_VERSION}_undercloud.conf.template | envsubst >~/undercloud.conf
echo "INFO: undercloud.conf"
cat ~/undercloud.conf

cd
openstack undercloud install
