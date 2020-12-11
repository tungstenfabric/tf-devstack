#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh

source $my_dir/../../common/common.sh
source $my_dir/../../common/functions.sh
source $my_dir/../providers/common/functions.sh

function _get_count()
{
   if [[ -n "$1" ]] ; then
      echo $(( $(echo $1 | grep -o ',' | wc -l) + 1))
   else
      echo 0
   fi
}

if [[ -n "$overcloud_ceph_instance" ]] ; then
   export glance_backend_storage="rbd"
else
   export glance_backend_storage="file"
fi

if [[ -n "$ENABLE_TLS" ]] ; then
   export overcloud_nameservers="[ \"$ipa_prov_ip\" ]"
else
   export overcloud_nameservers="[ \"8.8.8.8\", \"8.8.4.4\" ]"
fi

if (( $(_get_count $overcloud_cont_instance) > 1 )) ; then
   export enable_galera=true
else
   export enable_galera=false
fi

export undercloud_registry=${prov_ip}:8787
export undercloud_registry_contrail=$undercloud_registry
ns=$(echo ${CONTAINER_REGISTRY:-'docker.io/tungstenfabric'} | cut -s -d '/' -f2-)
[ -n "$ns" ] && undercloud_registry_contrail+="/$ns"
if [[ "$USE_PREDEPLOYED_NODES" == true ]]; then
   #Explicitly set to prevent the use of a network interface gateway
  export vrouter_gateway_parameter="VROUTER_GATEWAY: ${prov_ip}"
fi
if [[ "$ENABLE_RHEL_REGISTRATION" == false ]]; then
   export RHEL_REG_METHOD="disable"
else
   export RHEL_REG_METHOD="portal"
   #Getting orgID
   export RHEL_ORG_ID=$(sudo subscription-manager identity | grep "org ID" | sed -e 's/^.*: //')
fi

export SSH_PRIVATE_KEY=`while read l ; do echo "      $l" ; done < .ssh/id_rsa`
export SSH_PUBLIC_KEY=`while read l ; do echo "      $l" ; done < .ssh/id_rsa.pub`

cd
rm -rf tripleo-heat-templates contrail-tripleo-heat-templates
cp -r /usr/share/openstack-tripleo-heat-templates/ tripleo-heat-templates
fetch_deployer_no_docker "tf-tripleo-heat-templates-src" contrail-tripleo-heat-templates \
|| git clone https://github.com/tungstenfabric/tf-tripleo-heat-templates contrail-tripleo-heat-templates

if [[ ! -d contrail-tripleo-heat-templates ]] ; then
   echo "ERROR: The directory with src contrail-tripleo-heat-templates is not found. Exit with error"
   exit 1
fi
pushd contrail-tripleo-heat-templates
rhosp_branch="stable/${OPENSTACK_VERSION}"
git checkout ${rhosp_branch}
if [[ $? != 0 ]] ; then
   echo "ERROR: Checkout to ${rhosp_branch} is finished with error"
   exit 1
fi
popd
cp -r contrail-tripleo-heat-templates/* tripleo-heat-templates

#SRIOV parameters tuning
contrailsriovnumvfs="${sriov_physical_interface}:${sriov_vf_number}"
sed -i "s/ContrailSriovNumVFs:.*/ContrailSriovNumVFs: [\"$contrailsriovnumvfs\"]/" tripleo-heat-templates/environments/contrail/contrail-services.yaml
sed -i "s/devname: .*/devname: \"${sriov_physical_interface}\"/" tripleo-heat-templates/environments/contrail/contrail-services.yaml

cat $my_dir/misc_opts.yaml.template | envsubst > misc_opts.yaml

cat <<EOF >> misc_opts.yaml
  ControllerCount: $(_get_count $overcloud_cont_instance)
  ContrailControllerCount: $(_get_count $overcloud_ctrlcont_instance)
  ComputeCount: $(_get_count $overcloud_compute_instance)
  ContrailDpdkCount: $(_get_count $overcloud_dpdk_instance)
  ContrailSriovCount: $(_get_count $overcloud_sriov_instance)
  CephStorageCount: $(_get_count $overcloud_ceph_instance)
  CephDefaultPoolSize: 2
  CephPoolDefaultPgNum: 8
  ManilaCephFSDataPoolPGNum: 8
  ManilaCephFSMetadataPoolPGNum: 8
EOF

if [ -n "$vrouter_huge_pages_1g" ] ; then
  # use 1gb pages
  cat <<EOF >> misc_opts.yaml
  ContrailVrouterHugepages1GB: '$vrouter_huge_pages_1g'
  ContrailVrouterHugepages2MB: ''
  ComputeParameters:
    KernelArgs: "default_hugepagesz=1GB hugepagesz=1G hugepages=$vrouter_huge_pages_1g"
    ExtraSysctlSettings:
      vm.nr_hugepages:
        value: $vrouter_huge_pages_1g
      vm.max_map_count:
        value: 128960
EOF
else
  # use 2mb pages
  cat <<EOF >> misc_opts.yaml
  ContrailVrouterHugepages1GB: ''
  ContrailVrouterHugepages2MB: '512'
  ComputeParameters:
    KernelArgs: ''
    ExtraSysctlSettings:
      vm.nr_hugepages:
        value: 512
      vm.max_map_count:
        value: 128960
EOF
fi

#Creating rhosp specific contrail-parameters.yaml
source $my_dir/${RHOSP_VERSION}_prepare_heat_templates.sh
cat $my_dir/${RHOSP_VERSION}_contrail-parameters.yaml.template | envsubst > contrail-parameters.yaml

#Changing tripleo-heat-templates/roles_data_contrail_aio.yaml
if [[ -z "$overcloud_ctrlcont_instance" && -z "$overcloud_compute_instance" ]] ; then
   role_file=tripleo-heat-templates/roles/ContrailAio.yaml
   sed -i -re 's/Count:\s*[[:digit:]]+/Count: 0/' tripleo-heat-templates/environments/contrail/contrail-services.yaml
   sed -i -re 's/ContrailAioCount: 0/ContrailAioCount: 1/' tripleo-heat-templates/environments/contrail/contrail-services.yaml
else
   role_file=tripleo-heat-templates/roles_data_contrail_aio.yaml
fi
if [[ "$USE_PREDEPLOYED_NODES" == true ]]; then
   $my_dir/../../common/jinja2_render.py < $my_dir/ctlplane-assignments.yaml.j2 >ctlplane-assignments.yaml
   $my_dir/../../common/jinja2_render.py < $my_dir/hostname-map.yaml.j2 >hostname-map.yaml
   sed -i -re 's/disable_constraints: False/disable_constraints: True/' $role_file
fi

#Auto-detect physnet MTU for cloud environments
default_iface=`/sbin/ip route get 1 | grep -o "dev.*" | awk '{print $2}'`
default_iface_mtu=`/sbin/ip link show $default_iface | grep -o "mtu.*" | awk '{print $2}'`

if (( ${default_iface_mtu} < 1500 )); then
  echo -e "\n  NeutronGlobalPhysnetMtu: ${default_iface_mtu}" >> contrail-parameters.yaml
fi
