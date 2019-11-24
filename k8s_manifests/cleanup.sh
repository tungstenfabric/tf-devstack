#!/bin/bash

set -o errexit
set -x

# Targets are k8s, tf or empty for all
target=$1

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

if [[ -z $target || $target == "tf" ]]; then
  echo "Deleting contrail.yaml tf"
  [ $(rm ~/.tf/.stages/tf) ] || true
  [ $(rm ~/.tf/.stages/manifest) ] || true
  [[ $(kubectl delete -f contrail.yaml) ]] || true

  echo "Waiting for contrail pods to get removed"
  while [[ $(kubectl get pods --all-namespaces | grep contrail) ]]; do printf . ; sleep 1; done
fi

if [[ -z $target || $target == "k8s" ]]; then
  echo "Resetting kubespray"
  [ $(rm ~/.tf/.stages/k8s) ] || true
  ${my_dir}/../common/cleanup_kubespray.sh
fi
