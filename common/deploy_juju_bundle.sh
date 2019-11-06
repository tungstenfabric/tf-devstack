#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# parameters
BUNDLE_TEMPLATE=${BUNDLE_TEMPLATE:-}
ORCHESTRATOR=${ORCHESTRATOR:-'openstack'}
CLOUD=${CLOUD:-'aws'}
CONTROLLER_NODES=${CONTROLLER_NODES:-}

# parameters for rendering bundle yaml
export UBUNTU_SERIES=${UBUNTU_SERIES:-'bionic'}
export JUJU_REPO=${JUJU_REPO:-"$WORKSPACE/contrail-charms"}
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-'opencontrailnightly'}
export CONTRAIL_VERSION=${CONTRAIL_CONTAINER_TAG:-'master-latest'}

JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
export MACHINES=`echo $JUJU_MACHINES | sed 's/ /,/g'`

# change bundles variables
echo "INFO: Change variables in bundle..."
python3 "$my_dir/jinja2_render.py" <"${BUNDLE_TEMPLATE}" >"$WORKSPACE/bundle.yaml"

juju deploy $WORKSPACE/bundle.yaml --map-machines=existing
