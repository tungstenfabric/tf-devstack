#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source "$my_dir/../providers/common/common.sh"
source "$my_dir/../providers/common/functions.sh"

# ssh config to do not check host keys and avoid garbadge in known hosts files
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat <<EOF >~/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF
chmod 644 ~/.ssh/config

export local_mtu=`/sbin/ip link show $undercloud_local_interface | grep -o "mtu.*" | awk '{print $2}'`

if [[ -n "$ENABLE_TLS" ]] ; then
  export undercloud_nameservers="$ipa_prov_ip"
  export nova_join_option="enable_novajoin = True"
  export ipa_otp_option="ipa_otp = \"$OTP_PASSWORD\""
else
  export undercloud_nameservers="8.8.8.8"
  export nova_join_option=""
  export ipa_otp_option=""
fi

source $my_dir/${RHOSP_VERSION}_undercloud_deploy.sh
source $my_dir/${RHOSP_VERSION}_configure_registries_undercloud.sh
