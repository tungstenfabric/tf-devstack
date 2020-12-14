#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source $my_dir/../../../common/common.sh
source $my_dir/../../../common/functions.sh
source $my_dir/common.sh

attach_opts='--auto'
if [[ -n "$RHEL_POOL_ID" ]] ; then
   attach_opts="--pool $RHEL_POOL_ID"
fi

cd
sudo getenforce
sudo cat /etc/selinux/config

cat <<EOF | sudo tee /etc/sysctl.d/10-tf-devstack.conf
net.ipv6.bindv6only = 0
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system || true

function _register_system() {
   sudo subscription-manager unregister || true
   sudo subscription-manager register --username $RHEL_USER --password $RHEL_PASSWORD
}

if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   state="$(set +o)"
   [[ "$-" =~ e ]] && state+="; set -e"
   set +x
   echo "subscription-manager register system"
   wait_cmd_success _register_system 2 5
   eval "$state"
  
   echo "subscription-manager attach ... $i"
   wait_cmd_success "sudo subscription-manager attach $attach_opts" 2 5

   echo "subscription-manager clean repos ... $i"
   wait_cmd_success "sudo subscription-manager repos --disable=*" 2 5
   
   enable_repo_list=''
   for r in $(echo $RHEL_REPOS | tr ',' ' ') ; do enable_repo_list+=" --enable=${r}"; done
   echo "subscription-manager repos $enable_repo_list ... $i"
   wait_cmd_success "sudo subscription-manager repos $enable_repo_list" 2 5
else
   sudo subscription-manager config --rhsm.auto_enable_yum_plugins=0
   sudo subscription-manager config --rhsm.manage_repos=0
fi

source $my_dir/${RHEL_VERSION}_provisioning.sh

[[ "$ENABLE_TLS" != 'ipa' ]] || sudo update-ca-trust extract
