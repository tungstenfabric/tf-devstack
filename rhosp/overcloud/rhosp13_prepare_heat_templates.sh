

if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
  #Creating environment-rhel-registration.yaml
  cat $my_dir/environment-rhel-registration.yaml.template | envsubst > environment-rhel-registration.yaml
fi
