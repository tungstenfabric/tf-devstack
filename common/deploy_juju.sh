#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"
source "$my_dir/functions.sh"

# parameters
UBUNTU_SERIES=${UBUNTU_SERIES:-'bionic'}
CLOUD=${CLOUD:-'local'}
AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-''}
AWS_SECRET_KEY=${AWS_SECRET_KEY:-''}
AWS_REGION=${AWS_REGION:-'us-east-1'}

# install JuJu
#TODO: check snap in ubuntu xenial
sudo snap install juju --classic

# configure ssh to not check host keys and avoid garbadge in known hosts files
cat <<EOF > $HOME/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF

if [[ $CLOUD == 'aws' ]] ; then
    # configure juju to authentificate itself to amazon
    juju remove-credential aws aws &>/dev/null || /bin/true
    creds_file="/tmp/creds.yaml"
    cat >"$creds_file" <<EOF
credentials:
  aws:
    aws:
      auth-type: access-key
      access-key: $AWS_ACCESS_KEY
      secret-key: $AWS_SECRET_KEY
EOF
    juju add-credential aws -f "$creds_file"
    rm -f "$creds_file"
    juju set-default-region aws $AWS_REGION
fi

# bootstrap JuJu-controller
if [[ $CLOUD == 'local' ]] ; then
    # prepare ssh key authorization for running bootstrap on the same node
    set_ssh_keys

    CLOUD="manual/ubuntu@$NODE_IP"
    juju bootstrap --no-switch --bootstrap-series=$UBUNTU_SERIES $CLOUD tf-aio-controller
    juju switch tf-aio-controller
else
    juju bootstrap --bootstrap-series=$UBUNTU_SERIES $CLOUD tf-$CLOUD-controller
fi