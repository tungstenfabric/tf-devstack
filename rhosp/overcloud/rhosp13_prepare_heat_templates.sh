if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
  #Creating environment-rhel-registration.yaml
  cat $my_dir/environment-rhel-registration.yaml.template | envsubst > environment-rhel-registration.yaml
fi

cat $my_dir/firstboot_userdata.yaml.template | envsubst > firstboot_userdata.yaml
