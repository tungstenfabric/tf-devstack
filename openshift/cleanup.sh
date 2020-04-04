#!/bin/bash

set -o errexit
set -x

# Targets are k8s, tf or empty for all
target=$1

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

if [[ "$target" == "tf" ]]; then
  echo "Deleting tf resources"
  echo "ERROR: not supported for now"
  exit -1
fi

if [[  "$target" == "openshift" ]]; then
  echo "Uninstall openshift"
  echo "ERROR: not supported for now"
  exit -1
fi

if [[ -n "$target" ]] ; then
  echo "ERROR: unsupported target $target"
  exit -1
fi

deployer_dir=${WORKSPACE}/tf-openshift-ansible-src
cd $deployer_dir
sudo ansible-playbook -i $settings_file \
    -i inventory/hosts.aio.contrail playbooks/adhoc/uninstall_openshift.yml

sudo ifdown vhost0
