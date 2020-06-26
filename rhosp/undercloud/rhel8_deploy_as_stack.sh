#RHEL8 undercloud install
[ -n "$RHEL_USER" ] && rhsm_login_password="${RHEL_USER}: '${RHEL_PASSWORD}'"
cat containers-prepare-parameter.yaml.template | envsubst >~/containers-prepare-parameter.yaml
echo "INFO: containers-prepare-parameter.yaml"
cat ~/containers-prepare-parameter.yaml

cat ${RHEL_VERSION}_undercloud.conf.template | envsubst >~/undercloud.conf
echo "INFO: undercloud.conf"
cat ~/undercloud.conf

cd
openstack undercloud install
