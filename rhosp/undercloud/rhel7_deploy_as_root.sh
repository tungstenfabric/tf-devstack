
if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   yum-config-manager --enable rhelosp-rhel-7-server-opt
fi

yum -y install python-tripleoclient python-rdomanager-oscplugin iproute rhosp-director-images ceph-ansible
