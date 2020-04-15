#!/bin/bash -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   yum-config-manager --enable rhelosp-rhel-7-server-opt
fi

#yum -y install python-tripleoclient python-rdomanager-oscplugin  openstack-utils
yum -y install python-tripleoclient python-rdomanager-oscplugin iproute rhosp-director-images
