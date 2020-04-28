#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ~/rhosp-environment.sh
source "$my_dir/../../common/functions.sh"
source "$my_dir/../providers/common/functions.sh"

export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-"latest"}
rhosp_branch="stable/${OPENSTACK_VERSION}"
tf_rhosp_image="tf-tripleo-heat-templates-src"

cd
rm -rf ~/tripleo-heat-templates ~/contrail-tripleo-heat-templates
cp -r /usr/share/openstack-tripleo-heat-templates/ ~/tripleo-heat-templates
fetch_deployer_no_docker ${tf_rhosp_image} ~/contrail-tripleo-heat-templates \
|| git clone https://github.com/juniper/contrail-tripleo-heat-templates ~/contrail-tripleo-heat-templates

if [[ ! -d ~/contrail-tripleo-heat-templates ]] ; then
   echo "ERROR: The directory with src ~/contrail-tripleo-heat-templates is not found. Exit with error"
   exit 1
fi
pushd ~/contrail-tripleo-heat-templates
git checkout ${rhosp_branch}
if [[ $? != 0 ]] ; then
   echo "ERROR: Checkout to ${rhosp_branch} is finished with error"
   exit 1
fi
popd

cp -r ~/contrail-tripleo-heat-templates/* ~/tripleo-heat-templates

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
   if [[ -z "${overcloud_compute_prov_ip}" ]]; then
      sed  '${/^$/d;}' tripleo-heat-templates/roles/ContrailAio.yaml > tripleo-heat-templates/roles_data_contrail_aio.yaml
      sed -i -re 's/Count:\s*[[:digit:]]+/Count: 0/' tripleo-heat-templates/environments/contrail/contrail-services.yaml
      sed -i -re 's/ContrailAioCount: 0/ContrailAioCount: 1/' tripleo-heat-templates/environments/contrail/contrail-services.yaml
      cat $my_dir/ctlplane-assignments-aio.yaml.template | envsubst >~/ctlplane-assignments.yaml
   else
      cp $my_dir/roles_data_contrail_aio_without_node_introspection.yaml tripleo-heat-templates/roles_data_contrail_aio.yaml
      cat $my_dir/ctlplane-assignments-no-ha.yaml.template | envsubst >~/ctlplane-assignments.yaml
   fi
fi

#Auto-detect physnet MTU for cloud environments
default_iface=`/sbin/ip route get 1 | grep -o "dev.*" | awk '{print $2}'`
default_iface_mtu=`/sbin/ip link show $default_iface | grep -o "mtu.*" | awk '{print $2}'`

if (( ${default_iface_mtu} < 1500 )); then
  echo -e "\n  NeutronGlobalPhysnetMtu: ${default_iface_mtu}" >> ~/contrail-parameters.yaml
fi
