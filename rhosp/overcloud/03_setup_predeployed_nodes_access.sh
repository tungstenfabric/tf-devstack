#!/bin/bash

if [ -f /home/$SUDO_USER/rhosp-environment.sh ]; then
   source /home/$SUDO_USER/rhosp-environment.sh
else
   echo "File /home/$SUDO_USER/rhosp-environment.sh not found"
   exit
fi

if [ ! -f /usr/share/openstack-tripleo-heat-templates/deployed-server/scripts/enable-ssh-admin.sh ]; then
   echo "File /usr/share/openstack-tripleo-heat-templates/deployed-server/scripts/enable-ssh-admin.sh is not found"
   exit
fi

(
   source ~/stackrc
   export OVERCLOUD_HOSTS="${overcloud_cont_prov_ip} ${overcloud_compute_prov_ip} ${overcloud_ctrlcont_prov_ip}"
   bash -x /usr/share/openstack-tripleo-heat-templates/deployed-server/scripts/enable-ssh-admin.sh
) > /dev/null
