if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then

  #inserting repos
  for i in $(echo $RHEL_REPOS | tr ',' ' '); do
    sed -i "/rhsm_repos:/ a \ \ \ \ \ \ - $i" $my_dir/rhsm.yaml.template
  done

  declare -A _rhsm_releases=( ["rhosp13"]='7.9' ['rhosp16.1']='8.2' ['rhosp16.2']='8.4' )
  export RHSM_RELEASE=${_rhsm_releases[$RHOSP_VERSION]}
  cat $my_dir/rhsm.yaml.template | envsubst > rhsm.yaml
fi
