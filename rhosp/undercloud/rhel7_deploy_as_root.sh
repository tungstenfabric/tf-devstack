
if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   yum-config-manager --enable rhelosp-rhel-7-server-opt
fi

yum -y install python-tripleoclient python-rdomanager-oscplugin iproute rhosp-director-images

#ceph-ansible 3.1 requires Ansible version 2.4. Сontained in rhel-7-server-openstack-13-rpms
#ceph-ansible-3.2 requires Ansible version 2.6. Сontained in rhel-7-server-rhceph-3-tools-rpms
if [[ "$backend_storage" == "rbd" ]] ; then
   yum -y install ceph-ansible
fi
