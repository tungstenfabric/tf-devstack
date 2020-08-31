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
MAAS_ENDPOINT=${MAAS_ENDPOINT:-''}
MAAS_API_KEY=${MAAS_API_KEY:-''}

# install JuJu and tools
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update -y
sudo -E apt-get install snap netmask prips python3-jinja2 software-properties-common curl jq -y
sudo snap install --classic juju

# configure ssh to not check host keys and avoid garbadge in known hosts files
cat <<EOF > $HOME/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF
chmod 600 $HOME/.ssh/config

if [[ $CLOUD == 'aws' ]] ; then
    # configure juju to authentificate itself to amazon
    juju remove-credential --client aws aws &>/dev/null || /bin/true
    creds_file="/tmp/creds.yaml"
    cat >"$creds_file" <<EOF
credentials:
  aws:
    aws:
      auth-type: access-key
      access-key: $AWS_ACCESS_KEY
      secret-key: $AWS_SECRET_KEY
EOF
    juju add-credential --client aws -f "$creds_file"
    rm -f "$creds_file"
    juju set-default-region aws $AWS_REGION
fi

if [[ $CLOUD == 'maas' ]] ; then
    juju remove-credential --client maas tf-maas-cloud-creds &>/dev/null || /bin/true
    juju remove-cloud --client maas &>/dev/null || /bin/true
    cloud_file="/tmp/maas_cloud.yaml"
    creds_file="/tmp/maas_creds.yaml"
    cat >"$cloud_file" <<EOF
clouds:
  maas:
    type: maas
    auth-types: [oauth1]
    endpoint: $MAAS_ENDPOINT
EOF
    cat >"$creds_file" <<EOF
credentials:
  maas:
    tf-maas-cloud-creds:
      auth-type: oauth1
      maas-oauth: $MAAS_API_KEY
EOF
    juju add-cloud --local maas -f $cloud_file
    juju add-credential --client maas -f $creds_file
    rm -f "$cloud_file $creds_file"
fi

# prepare ssh key authorization for running bootstrap on the same node
set_ssh_keys

# bootstrap JuJu-controller
if [[ $CLOUD == 'aws' ]]; then
    juju bootstrap --no-switch --bootstrap-series=$UBUNTU_SERIES --bootstrap-constraints "mem=31G cores=8 root-disk=120G" $CLOUD tf-$CLOUD-controller
elif [[ $CLOUD == 'maas' ]]; then
    juju bootstrap --bootstrap-series=$UBUNTU_SERIES --bootstrap-constraints "mem=4G cores=2 root-disk=40G" $CLOUD tf-$CLOUD-controller
elif [[ $CLOUD == 'local' ]]; then
    juju bootstrap --no-switch --bootstrap-series=$UBUNTU_SERIES manual/ubuntu@$NODE_IP tf-$CLOUD-controller
elif [[ $CLOUD == 'manual' ]]; then
    juju bootstrap --config container-networking-method=fan --config fan-config=$NODE_CIDR=252.0.0.0/8 --bootstrap-series=$UBUNTU_SERIES manual/ubuntu@$NODE_IP tf-$CLOUD-controller
else
    echo "ERROR: unknown type of cloud: $CLOUD"
    exit 1
fi
if [[ $CLOUD != 'manual' ]]; then
    juju switch tf-$CLOUD-controller
fi

juju model-config logging-config="<root>=DEBUG"
