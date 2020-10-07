
if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   yum-config-manager --enable rhelosp-rhel-7-server-opt
fi

yum -y install python-tripleoclient python-rdomanager-oscplugin iproute rhosp-director-images

# ceph-ansible v3.1 contained in rhel-7-server-openstack-13-rpms requires ansible v2.4
# ceph-ansible v3.2 contained in rhel-7-server-rhceph-3-tools-rpms requires ansible v2.6 
if [[ "$backend_storage" == "rbd" ]] ; then
   yum -y install ceph-ansible
fi
