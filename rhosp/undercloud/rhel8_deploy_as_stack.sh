#RHEL8 undercloud install

cat containers-prepare-parameter.yaml.template | envsubst >~/containers-prepare-parameter.yaml

cat ${RHEL_VERSION}_undercloud.conf.template | envsubst >~/undercloud.conf

openstack undercloud install

