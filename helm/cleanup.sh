#!/bin/bash

set -o errexit
set -x

# Targets are k8s, tf or empty for all
target=$1

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

if [[ -z $target || $target == "tf" ]]; then
  echo "Deleting tf helm charts"
  [ $(rm ~/.tf/.stages/tf) ] || true
  [ $(helm ls --namespace tungsten-fabric --short | xargs -r -L1 -P2 helm delete --purge) ] || true
fi

# TODO: Not checked
if [[ -z $target || $target == "openstack" ]]; then
  echo "Deleting contrail.yaml tf"
  [ $(rm ~/.tf/.stages/openstack) ] || true
  for NS in openstack nfs libvirt; do
    [ $(helm ls --namespace $NS --short | xargs -r -L1 -P2 helm delete --purge) ] || true
  done
fi

if [[ -z $target || $target == "k8s" ]]; then
  echo "Resetting kubespray"
  [ $(rm ~/.tf/.stages/k8s) ] || true
  ${my_dir}/../common/cleanup_kubespray.sh
fi
