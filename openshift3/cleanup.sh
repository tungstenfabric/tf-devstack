#!/bin/bash

set -o errexit
set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

deployer_dir=${WORKSPACE}/tf-openshift-ansible-src
settings_file=${WORKSPACE}/tf_openhift_settings

if [ -d "$deployer_dir" ] ; then
  pushd $deployer_dir
  ansible-playbook -i $settings_file \
    -i inventory/hosts.aio.contrail playbooks/adhoc/uninstall_openshift.yml
  popd
fi

sudo -E $my_dir/cleanup-root.sh
