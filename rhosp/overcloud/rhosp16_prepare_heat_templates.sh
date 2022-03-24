if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then

  #inserting repos
  for i in $(echo $RHEL_REPOS | tr ',' ' '); do
    sed -i "/rhsm_repos:/ a \ \ \ \ \ \ - $i" $my_dir/rhsm.yaml.template
  done

  cat $my_dir/rhsm.yaml.template | envsubst > rhsm.yaml
fi

if [[ -n "$overcloud_dpdk_instance" ]]; then
  #Changing network interfaces for baremetal dpdk node in openlab1
  echo "INFO Changing network template for openlab1 contrail-dpdk-nic-config-single.yaml"
  sed -i "s/nic1/nic3/" tripleo-heat-templates/network/config/contrail/contrail-dpdk-nic-config-single.yaml
  sed -i "s/nic2/nic4/" tripleo-heat-templates/network/config/contrail/contrail-dpdk-nic-config-single.yaml
fi

if [[ -n "$overcloud_sriov_instance" ]]; then
  #Changing network interfaces for baremetal sriov node in openlab1
  echo "INFO Changing network template for openlab1 contrail-sriov-nic-config.yaml"
  sed -i "s/nic1/nic3/" tripleo-heat-templates/network/config/contrail/contrail-sriov-nic-config.yaml
  sed -i "s/nic2/nic4/" tripleo-heat-templates/network/config/contrail/contrail-sriov-nic-config.yaml
fi

