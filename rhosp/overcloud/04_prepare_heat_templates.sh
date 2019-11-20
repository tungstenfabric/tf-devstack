#!/bin/bash

cd

if [[ `whoami` !=  'stack' ]]; then
   echo "This script must be run by user 'stack'"
   exit 1
fi

# RHEL Registration
set +x
if [ -f ~/rhel-account.rc ]; then
   source ~/rhel-account.rc
else
   echo "File ~/rhel-account.rc not found"
   exit
fi

if [ -f ~/env.sh ]; then
   source ~/env.sh
else
   echo "File ~/env.sh not found"
   exit
fi


cp -r /usr/share/openstack-tripleo-heat-templates/ ~/tripleo-heat-templates

git clone https://github.com/juniper/contrail-tripleo-heat-templates -b stable/queens

cp -r ~/contrail-tripleo-heat-templates/* ~/tripleo-heat-templates

role_file='tripleo-heat-templates/roles_data_contrail_aio.yaml'

export SSH_PRIVATE_KEY=`while read l ; do echo "      $l" ; done < ~/.ssh/id_rsa`
export SSH_PUBLIC_KEY=`while read l ; do echo "      $l" ; done < ~/.ssh/id_rsa.pub`

cat overcloud/misc_opts.yaml.template | envsubst >~/misc_opts.yaml

#Creating environment-rhel-registration.yaml
cat overcloud/environment-rhel-registration.yaml.template | envsubst >~/environment-rhel-registration.yaml

#Creating environment-rhel-registration.yaml
cat overcloud/contrail-parameters.yaml.template | envsubst >~/contrail-parameters.yaml

#Changing tripleo-heat-templates/roles_data_contrail_aio.yaml
cp overcloud/roles_data_contrail_aio.yaml tripleo-heat-templates/roles_data_contrail_aio.yaml

