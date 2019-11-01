#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

WORKSPACE="$(pwd)"

#TODO: CONTROLLER_NODES is a list
juju_node_ip=${CONTROLLER_NODES}

# default env variables
export SERIES=${SERIES:-bionic}
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-opencontrailnightly}
export CONTRAIL_VERSION=${CONTRAIL_CONTAINER_TAG:-master-latest}
export JUJU_REPO=${JUJU_REPO:-$WORKSPACE/contrail-charms}

[ -d $WORKSPACE/contrail-charms ] || git clone --depth 1 --single-branch https://github.com/Juniper/contrail-charms -b R5 $WORKSPACE/contrail-charms
cd $WORKSPACE/contrail-charms

# prepare ssh key authorization for all-in-one single node deployment
[ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
[ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
[ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

cat <<EOF > $HOME/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF

#TODO: check snap in ubuntu xenial
sudo snap install juju --classic

juju bootstrap manual/ubuntu@${NODE_IP} juju-cont
export JUJU_DEPLOY_MCH=`juju add-machine ssh:ubuntu@$juju_node_ip 2>&1 | tail -1 | awk '{print $3}'`

# change bundles variables
echo "INFO: Change variables in bundle..."
python3 "$my_dir/../common/jinja2_render.py" <"$my_dir/bundle.yaml.tmpl" >"$my_dir/bundle.yaml"

juju deploy $my_dir/bundle.yaml --map-machines=existing

# fix /etc/hosts
juju_node_hostname=`juju ssh $JUJU_DEPLOY_MCH "hostname" | tr -d '\r'`
juju ssh $JUJU_DEPLOY_MCH "sudo bash -c 'echo $juju_node_ip $juju_node_hostname >> /etc/hosts'" 2>/dev/null

# show results
echo "Deployment scripts are finished"
echo "Now you can monitor when contrail becomes available with:"
echo "juju status"
echo "All applications and units should become active, before you can use Contrail"
echo "Contrail Web UI will be available at https://$NODE_IP:8143"
