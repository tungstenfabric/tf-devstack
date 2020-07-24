#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ~/rhosp-environment.sh
source "$my_dir/../../common/functions.sh"
source "$my_dir/../providers/common/functions.sh"

export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-"latest"}

if [[ -n "$ENABLE_TLS" ]] ; then
   export overcloud_nameservers="[ \"$ipa_prov_ip\" ]"
else
   export overcloud_nameservers="[ \"8.8.8.8\", \"8.8.4.4\" ]"
fi

rhosp_branch="stable/${OPENSTACK_VERSION}"
tf_rhosp_image="tf-tripleo-heat-templates-src"

cd
rm -rf ~/tripleo-heat-templates ~/contrail-tripleo-heat-templates
cp -r /usr/share/openstack-tripleo-heat-templates/ ~/tripleo-heat-templates
fetch_deployer_no_docker ${tf_rhosp_image} ~/contrail-tripleo-heat-templates \
|| git clone https://github.com/tungstenfabric/tf-tripleo-heat-templates ~/contrail-tripleo-heat-templates

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
if [[ "$PROVIDER" == "bmc" ]]; then
  echo "  ControllerCount: 3" >> ~/misc_opts.yaml
  echo "  ContrailControllerCount: 3" >> ~/misc_opts.yaml
  echo "  ComputeCount: 2" >> ~/misc_opts.yaml
  echo "  node_admin_username: ${SSH_USER}" >> ~/misc_opts.yaml
fi

#Creating file for overcloud rhel registration (rhosp version specific)
if [[ "$ENABLE_RHEL_REGISTRATION" == false ]]; then
   export RHEL_REG_METHOD="disable"
else
   export RHEL_REG_METHOD="portal"
fi
source $my_dir/${RHOSP_VERSION}_prepare_heat_templates.sh

#Creating contrail-parameters.yaml
export undercloud_registry=${prov_ip}:8787
export undercloud_registry_contrail=$undercloud_registry
ns=$(echo ${CONTAINER_REGISTRY:-'docker.io/tungstenfabric'} | cut -s -d '/' -f2-)
[ -n "$ns" ] && undercloud_registry_contrail+="/$ns"
#Explicitly set to prevent the use of a network interface gateway
if [[ "$USE_PREDEPLOYED_NODES" == true ]]; then
  export vrouter_gateway_parameter="VROUTER_GATEWAY: ${prov_ip}"
fi
cat $my_dir/${RHOSP_VERSION}_contrail-parameters.yaml.template | envsubst > ~/contrail-parameters.yaml

#Changing tripleo-heat-templates/roles_data_contrail_aio.yaml
if [[ "${DEPLOY_COMPACT_AIO,,}" == 'true' ]] ; then
   role_file=~/tripleo-heat-templates/roles/ContrailAio.yaml
   sed -i -re 's/Count:\s*[[:digit:]]+/Count: 0/' tripleo-heat-templates/environments/contrail/contrail-services.yaml
   sed -i -re 's/ContrailAioCount: 0/ContrailAioCount: 1/' tripleo-heat-templates/environments/contrail/contrail-services.yaml
else
   role_file=~/tripleo-heat-templates/roles_data_contrail_aio.yaml
fi
if [[ "$USE_PREDEPLOYED_NODES" == true ]]; then
   if [[ "${DEPLOY_COMPACT_AIO,,}" == 'true' ]] ; then
      cat $my_dir/ctlplane-assignments-aio.yaml.template | envsubst >~/ctlplane-assignments.yaml
      cat $my_dir/hostname-map-aio.yaml.template | envsubst >~/hostname-map.yaml
   else
      cat $my_dir/ctlplane-assignments-no-ha.yaml.template | envsubst >~/ctlplane-assignments.yaml
      cat $my_dir/hostname-map-no-ha.yaml.template | envsubst >~/hostname-map.yaml
   fi
   sed -i -re 's/disable_constraints: False/disable_constraints: True/' $role_file
fi

#Auto-detect physnet MTU for cloud environments
default_iface=`/sbin/ip route get 1 | grep -o "dev.*" | awk '{print $2}'`
default_iface_mtu=`/sbin/ip link show $default_iface | grep -o "mtu.*" | awk '{print $2}'`

if (( ${default_iface_mtu} < 1500 )); then
  echo -e "\n  NeutronGlobalPhysnetMtu: ${default_iface_mtu}" >> ~/contrail-parameters.yaml
fi
