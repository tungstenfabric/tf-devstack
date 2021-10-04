#!/bin/bash -e

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"

source "$my_dir/../../../common/functions.sh"
source "$my_dir/../../definitions.sh"
source "$my_dir/../../functions.sh"
source "$my_dir/definitions"
source "$my_dir/functions"

cat <<EOF >/tmp/patch
data:
  requestheader-client-ca-file: |
$(while IFS= read -a line; do echo "    $line"; done < <(ssh ${SSH_OPTS} core@${BOOTSTRAP_DEFAULT_ADDRESS} 'sudo cat /etc/kubernetes/bootstrap-secrets/aggregator-ca.crt'))
EOF

kubectl -n kube-system patch configmap extension-apiserver-authentication --patch-file /tmp/patch
