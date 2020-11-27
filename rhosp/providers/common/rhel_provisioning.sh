#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source $my_dir/../../../common/common.sh
source $my_dir/../common/common.sh
source $my_dir/common.sh

attach_opts='--auto'
if [[ -n "$RHEL_POOL_ID" ]] ; then
   attach_opts="--pool $RHEL_POOL_ID"
fi

cd
sudo getenforce
sudo cat /etc/selinux/config

function _register_system() {
   sudo subscription-manager unregister || true
   sudo subscription-manager register $@
}

if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   [[ "$-" =~ e ]] && state+="; set -e"
   set +x
   echo "subscription-manager register system"
   eval "$state"
  
   echo "subscription-manager attach ... $i"
   retry sudo subscription-manager attach $attach_opts

   echo "subscription-manager clean repos ... $i"
   retry sudo subscription-manager repos --disable=*
   
   echo "subscription-manager repos $enable_repo_list ... $i"
   enable_repo_list=''
   for r in $(echo $RHEL_REPOS | tr ',' ' ') ; do enable_repo_list+=" --enable=${r}"; done
   retry sudo subscription-manager repos $enable_repo_list
else
   sudo subscription-manager config --rhsm.manage_repos=0
fi

$my_dir/${RHEL_VERSION}_provisioning.sh
