
if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   yum-config-manager --enable rhelosp-rhel-7-server-opt
fi

yum -y install python-tripleoclient python-rdomanager-oscplugin iproute rhosp-director-images

# ceph-ansible v3.1 requires Ansible v2.4 contained in rhel-7-server-openstack-13-rpms
# ceph-ansible v3.2 requires Ansible v2.6 contained in rhel-7-server-rhceph-3-tools-rpms
if [[ "$backend_storage" == "rbd" ]] ; then
   yum -y install ceph-ansible
fi
