#RHEL7 undercloud install

cat ${RHEL_VERSION}_undercloud.conf.template | envsubst >~/undercloud.conf
echo "INFO: undercloud.conf"
cat ~/undercloud.conf

openstack undercloud install

#Adding user to group docker
user=$(whoami)
sudo usermod -a -G docker $user

echo User "$user" has been added to group "docker". Please relogin


