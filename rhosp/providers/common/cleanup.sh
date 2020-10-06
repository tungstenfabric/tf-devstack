
source stackrc

if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
  sudo subscription-manager unregister
  servers=$(openstack server list -c Networks -f value | awk -F '=' '{print $NF}')
  for server in $servers; do
    ssh -T heat-admin@${server} "sudo subscription-manager unregister"
  done
fi

rm -rf .tf
