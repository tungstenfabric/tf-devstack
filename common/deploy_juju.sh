#!/bin/bash

set -o errexit

# parameters
UBUNTU_SERIES=${UBUNTU_SERIES:-'bionic'}
CLOUD=${CLOUD:-'aws'}
AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-''}
AWS_SECRET_KEY=${AWS_SECRET_KEY:-''}
AWS_REGION=${AWS_REGION:-'us-east-1'}
HOST_IP=${NODE_IP:-}

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

if [[ $CLOUD == 'manual' ]] ; then
    # prepare ssh key authorization for running bootstrap on the same node
    [ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
    [ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
    [ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
    grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
fi

if [[ $CLOUD == 'manual' ]]; then
    CLOUD="manual/ubuntu@$HOST_IP"
fi

# bootstrap JuJu-controller
juju bootstrap --bootstrap-series=$UBUNTU_SERIES $CLOUD tf-juju-controller
