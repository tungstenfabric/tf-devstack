
#Creating rhsm.yaml from template

if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then

  #inserting repos
  for i in `echo $RHEL_REPOS`; do
    sed -i "/rhsm_repos:/ a \ \ \ \ \ \ - $i" $my_dir/rhsm.yaml.template
  done

  #Getting orgID
  export RHEL_ORG_ID=$(sudo subscription-manager identity | grep "org ID" | sed -e 's/^.*: //')

  cat $my_dir/rhsm.yaml.template | envsubst > rhsm.yaml
fi
