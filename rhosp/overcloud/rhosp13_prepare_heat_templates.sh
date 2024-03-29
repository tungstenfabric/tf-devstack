if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
  #Creating environment-rhel-registration.yaml
  cat $my_dir/environment-rhel-registration.yaml.template | envsubst > environment-rhel-registration.yaml
fi

cat $my_dir/firstboot_userdata.yaml.template | envsubst > firstboot_userdata.yaml

if [[ -n "$overcloud_dpdk_instance" ]]; then
  #Changing network interfaces for baremetal dpdk node in openlab1
  echo "INFO: Changing network template for openlab1 contrail-dpdk-nic-config-single.yaml"
  sed -i "s/nic1/nic3/" tripleo-heat-templates/network/config/contrail/contrail-dpdk-nic-config-single.yaml
  sed -i "s/nic2/nic4/" tripleo-heat-templates/network/config/contrail/contrail-dpdk-nic-config-single.yaml
fi

if [[ -n "$overcloud_sriov_instance" ]]; then
  #Changing network interfaces for baremetal sriov node in openlab1
  echo "INFO Changing network template for openlab1 contrail-sriov-nic-config.yaml"
  sed -i "s/nic1/nic3/" tripleo-heat-templates/network/config/contrail/contrail-sriov-nic-config.yaml
  sed -i "s/nic2/nic4/" tripleo-heat-templates/network/config/contrail/contrail-sriov-nic-config.yaml
fi

#Patch ipaclient.yaml for checking /etc/resolv.conf (sometimes ipa dns server disappears from resolv.conf. Race condition or something)
if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
  pushd tripleo-heat-templates/extraconfig/services/
  echo "INFO: Changing extraconfig/services/ipaclient.yaml for preventing resolv.conf issue"
  patch ipaclient.yaml $my_dir/ipaclient.patch
  popd
fi

