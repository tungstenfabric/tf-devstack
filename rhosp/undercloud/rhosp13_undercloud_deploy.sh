#RHEL7 undercloud install

if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   sudo yum-config-manager --enable rhelosp-rhel-7-server-opt
fi

sudo yum -y install python-tripleoclient python-rdomanager-oscplugin iproute rhosp-director-images

cat ${RHOSP_VERSION}_undercloud.conf.template | envsubst >~/undercloud.conf
echo "INFO: undercloud.conf"
cat ~/undercloud.conf

openstack undercloud install

#Adding user to group docker
user=$(whoami)
sudo usermod -a -G docker $user

echo User "$user" has been added to group "docker". Please relogin
