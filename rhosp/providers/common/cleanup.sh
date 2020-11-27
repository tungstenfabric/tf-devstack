
#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source $my_dir/../../../common/common.sh
source $my_dir/../../../common/functions.sh
source $my_dir/common.sh
source $my_dir/functions.sh

if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
  sudo subscription-manager unregister

  servers=$(get_ctlplane_ips)
  for server in $servers; do
    ssh -T $ssh_opts $SSH_USER_OVERCLOUD@${server} "sudo subscription-manager unregister"
  done
fi

rm -rf .tf
