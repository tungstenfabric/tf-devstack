#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

juju_node_ip=${NODE_IP}

# default env variables
export SERIES=${SERIES:-bionic}
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-opencontrailnightly}
export CONTRAIL_VERSION=${CONTRAIL_CONTAINER_TAG:-master-latest}
export JUJU_REPO=${JUJU_REPO:-$my_dir/contrail-charms}

# TODO: if already cloned
git clone https://github.com/Juniper/contrail-charms -b R5
cd ./contrail-charms

cat <<EOF >/home/stack/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF

sudo snap install juju --classic

# TODO(tikitavi): get current node ip
juju bootstrap manual/ubuntu@$current_node_ip juju-cont
export juju_deploy_mch=`juju add-machine ssh:ubuntu@$juju_node_ip 2>&1 | tail -1 | awk '{print $3}'`

# change bundles variables
echo "INFO: Change variables in bundle..."
python3 "$my_dir/../common/jinja2_render.py" <"$my_dir/bundle.yaml.tmpl" >"$my_dir/bundle.yaml"

juju deploy $my_dir/bundle.yaml --map-machines=existing

# fix /etc/hosts
juju_node_hostname=`juju-ssh $juju_deploy_mch "hostname" | tr -d '\r'`
juju-ssh $juju_deploy_mch "sudo bash -c 'echo $juju_node_ip $juju_node_hostname >> /etc/hosts'" 2>/dev/null

# TODO: wait for services
# echo "INFO: Waiting for services start: $(date)"

# if ! wait_absence_status_for_services "executing|blocked|waiting" 45 ; then
#   echo "ERROR: Waiting for services end: $(date)"
#   return 1
# fi
# echo "INFO: Waiting for services end: $(date)"

# # check for errors
# if juju status | grep "current" | grep error ; then
#   echo "ERROR: Some services went to error state"
#   return 1
# fi

