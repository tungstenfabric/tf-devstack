#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source rhosp-environment.sh
source $my_dir/common.sh

attach_opts='--auto'
if [[ -n "$RHEL_POOL_ID" ]] ; then
   attach_opts="--pool $RHEL_POOL_ID"
fi

cd
sudo getenforce
sudo cat /etc/selinux/config
if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   set +x
   register_opts=''
   [ -n "$RHEL_USER" ] && register_opts+=" --username $RHEL_USER"
   [ -n "$RHEL_PASSWORD" ] && register_opts+=" --password $RHEL_PASSWORD"

   for i in {1..10} ; do
      sudo subscription-manager unregister || true
      echo subscription-manager register ... $i
      sudo subscription-manager register $register_opts && break
   done
   for i in {1..10} ; do
      echo subscription-manager attach ... $i
      sudo subscription-manager attach $attach_opts && break
   done
   set -x
   for i in {1..10} ; do
      echo subscription-manager clean repos ... $i
      sudo subscription-manager repos --disable=* && break
   done
   enable_repo_list=''
   for r in $(echo $RHEL_REPOS | tr ',' ' ') ; do enable_repo_list+=" --enable=${r}"; done
   for i in {1..10} ; do
      echo subscription-manager repos $enable_repo_list ... $i
      sudo subscription-manager repos $enable_repo_list && break
   done
fi

$my_dir/${RHEL_VERSION}_provisioning.sh
