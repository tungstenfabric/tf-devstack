#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source $my_dir/../../common/common.sh
source $my_dir/../providers/common/common.sh
source $my_dir/../providers/common/functions.sh


if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
  export undercloud_nameservers="$ipa_prov_ip"
  export nova_join_option="enable_novajoin = True"
  export ipa_otp_option="ipa_otp = \"$OTP_PASSWORD\""
else
  export undercloud_nameservers="8.8.8.8"
  export nova_join_option=""
  export ipa_otp_option=""
fi

export local_mtu=`/sbin/ip link show $undercloud_local_interface | grep -o "mtu.*" | awk '{print $2}'`

source $my_dir/${RHOSP_VERSION}_undercloud_deploy.sh
source $my_dir/${RHOSP_VERSION}_configure_registries_undercloud.sh
