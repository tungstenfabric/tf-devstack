#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
export ENABLE_RHEL_REGISTRATION=${ENABLE_RHEL_REGISTRATION:-'true'}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ -z ${RHEL_USER+x} && -z ${RHEL_PASSWORD+x} && -z ${RHEL_POOL_ID+x} ]]; then
   echo "Stop. Please define variables RHEL_USER, RHEL_PASSWORD and RHEL_POOL_ID"
   exit 1
fi

set +x
register_opts=''
[ -n "$RHEL_USER" ] && register_opts+=" --username $RHEL_USER"
[ -n "$RHEL_PASSWORD" ] && register_opts+=" --password $RHEL_PASSWORD"

attach_opts='--auto'
if [[ -n "$RHEL_POOL_ID" ]] ; then
   attach_opts="--pool $RHEL_POOL_ID"
fi

cd
getenforce
cat /etc/selinux/config
if [[ "${ENABLE_RHEL_REGISTRATION}" == 'true' ]] ; then
   subscription-manager unregister || true
   echo subscription-manager register ...
   subscription-manager register $register_opts
   subscription-manager attach $attach_opts

   set -x

   subscription-manager repos --disable=*

   enable_repo_list=''
   for r in $RHEL_REPOS; do enable_repo_list+=" --enable=${r}"; done
   subscription-manager repos $enable_repo_list
fi

$my_dir/${RHEL_VERSION}_provisioning.sh
