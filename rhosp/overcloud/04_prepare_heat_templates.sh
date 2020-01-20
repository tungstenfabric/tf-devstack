#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export user=$(whoami)

if [ -f ~/rhosp-environment.sh ]; then
   source ~/rhosp-environment.sh
else
   echo "File ~/rhosp-environment.sh not found"
   exit
fi

if [ -d ~/tripleo-heat-templates ]; then
   echo Old directory ~/tripleo-heat-templates found. Cleaning
   rm -rf ~/tripleo-heat-templates
fi

if [ -d ~/contrail-tripleo-heat-templates ]; then
   echo Old directory ~/contrail-tripleo-heat-templates found. Cleaning
   rm -rf ~/contrail-tripleo-heat-templates
fi


cp -r /usr/share/openstack-tripleo-heat-templates/ ~/tripleo-heat-templates

cd
git clone https://github.com/juniper/contrail-tripleo-heat-templates -b stable/queens

cp -r ~/contrail-tripleo-heat-templates/* ~/tripleo-heat-templates

export SSH_PRIVATE_KEY=`while read l ; do echo "      $l" ; done < ~/.ssh/id_rsa`
export SSH_PUBLIC_KEY=`while read l ; do echo "      $l" ; done < ~/.ssh/id_rsa.pub`

cat $my_dir/misc_opts.yaml.template | envsubst >~/misc_opts.yaml

#Creating environment-rhel-registration.yaml
cat $my_dir/environment-rhel-registration.yaml.template | envsubst >~/environment-rhel-registration.yaml

#Creating environment-rhel-registration.yaml
cat $my_dir/contrail-parameters.yaml.template | envsubst >~/contrail-parameters.yaml

#Changing tripleo-heat-templates/roles_data_contrail_aio.yaml
if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
   cp $my_dir/roles_data_contrail_aio.yaml tripleo-heat-templates/roles_data_contrail_aio.yaml
else
   cat $my_dir/ctlplane-assignments.yaml.template | envsubst >~/ctlplane-assignments.yaml
   cp $my_dir/roles_data_contrail_aio_without_node_introspection.yaml tripleo-heat-templates/roles_data_contrail_aio.yaml
fi

#Auto-detect physnet MTU for cloud environments
default_iface=`ip route get 1 | grep -o "dev.*" | awk '{print $2}'`
default_iface_mtu=`ip link show $default_iface | grep -o "mtu.*" | awk '{print $2}'`

if (( ${default_iface_mtu} < 1500 )); then
  echo "  NeutronGlobalPhysnetMtu: ${default_iface_mtu}" >> ~/contrail-parameters.yaml
fi



