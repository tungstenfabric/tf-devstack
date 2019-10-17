#!/bin/bash

set -o errexit
set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

echo "Deleting contrail.yaml manifest"
[[ $(kubectl delete -f contrail.yaml) ]] || true

echo "Waiting for contrail pods to get removed"
while [[ $(kubectl get pods --all-namespaces | grep contrail) ]]; do printf . ; sleep 1; done

echo "Resetting kubespray"
${my_dir}/../kubespray/cleanup_kubespray.sh
