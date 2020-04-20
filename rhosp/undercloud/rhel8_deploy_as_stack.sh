#RHEL8 undercloud install

cat containers-prepare-parameter.yaml.template | envsubst >~/containers-prepare-parameter.yaml

export undercloud_admin_host="${prov_subnet}.3"
export undercloud_public_host="${prov_subnet}.4"
cat ${RHEL_VERSION}_undercloud.conf.template | envsubst >~/undercloud.conf

openstack undercloud install

