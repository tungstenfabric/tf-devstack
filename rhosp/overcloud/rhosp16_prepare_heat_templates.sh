
#Creating rhsm.yaml from template

if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then

  #inserting repos
  for i in $(echo $RHEL_REPOS | tr ',' ' '); do
    sed -i "/rhsm_repos:/ a \ \ \ \ \ \ - $i" $my_dir/rhsm.yaml.template
  done

  cat $my_dir/rhsm.yaml.template | envsubst > rhsm.yaml
fi
