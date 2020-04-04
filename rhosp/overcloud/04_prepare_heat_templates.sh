#!/bin/bash
set -x
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../../common/functions.sh"
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-"${prov_ip}:8787/tungstenfabric"}
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-"${CONTRAIL_VERSION}"}
export user=$(whoami)
rhosp_branch="stable/${OPENSTACK_VERSION}"
tf_rhosp_image="tf-tripleo-heat-templates-src"
contrail_heat_templates_dir="${my_dir}/contrail-tripleo-heat-templates"
if [ -f ~/rhosp-environment.sh ]; then
   source ~/rhosp-environment.sh
else
   echo "File ~/rhosp-environment.sh not found"
   exit
fi

if [ -d ~/tripleo-heat-templates ] ; then
   echo Old directory ~/tripleo-heat-templates found. Cleaning
   rm -rf ~/tripleo-heat-templates
fi

if [ -d "${contrail_heat_templates_dir}" ] ; then
   echo "Old directory ${contrail_heat_templates_dir} found. Cleaning"
   rm -rf ${contrail_heat_templates_dir}
fi


cp -r /usr/share/openstack-tripleo-heat-templates/ ~/tripleo-heat-templates
cd
fetch_deployer_no_docker ${tf_rhosp_image} ${contrail_heat_templates_dir} \
|| git clone https://github.com/juniper/contrail-tripleo-heat-templates ${contrail_heat_templates_dir}

if [[ -d "${contrail_heat_templates_dir}" ]] ; then
   pushd ${contrail_heat_templates_dir}
   git checkout ${rhosp_branch}
   if [[ $? != 0 ]] ; then
      echo "ERROR: Checkout to ${rhosp_branch} is finished with error"
      exit 1
   fi
   popd
else
   echo "ERROR: The directory with src ${contrail_heat_templates_dir} is not found. Exit with error"
   exit 1
fi

cp -r ${contrail_heat_templates_dir}/* ~/tripleo-heat-templates

export SSH_PRIVATE_KEY=`while read l ; do echo "      $l" ; done < ~/.ssh/id_rsa`
export SSH_PUBLIC_KEY=`while read l ; do echo "      $l" ; done < ~/.ssh/id_rsa.pub`

cat $my_dir/misc_opts.yaml.template | envsubst > ~/misc_opts.yaml

#Creating environment-rhel-registration.yaml
cat $my_dir/environment-rhel-registration.yaml.template | envsubst > ~/environment-rhel-registration.yaml

#Creating environment-rhel-registration.yaml
cat $my_dir/contrail-parameters.yaml.template | envsubst > ~/contrail-parameters.yaml

#Changing tripleo-heat-templates/roles_data_contrail_aio.yaml
if [[ "$USE_PREDEPLOYED_NODES" == false ]]; then
   cp $my_dir/roles_data_contrail_aio.yaml tripleo-heat-templates/roles_data_contrail_aio.yaml
else
   cat $my_dir/ctlplane-assignments.yaml.template | envsubst >~/ctlplane-assignments.yaml
   cp $my_dir/roles_data_contrail_aio_without_node_introspection.yaml tripleo-heat-templates/roles_data_contrail_aio.yaml
fi

#Auto-detect physnet MTU for cloud environments
default_iface=`/sbin/ip route get 1 | grep -o "dev.*" | awk '{print $2}'`
default_iface_mtu=`/sbin/ip link show $default_iface | grep -o "mtu.*" | awk '{print $2}'`

if (( ${default_iface_mtu} < 1500 )); then
  echo "  NeutronGlobalPhysnetMtu: ${default_iface_mtu}" >> ~/contrail-parameters.yaml
fi
