#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"
source "$my_dir/functions.sh"

# parameters
BUNDLE=${BUNDLE:-} # may be template, would be rendered by jinja

# get list of machines to supply to bundle template, because machine indexes can change
JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
export JUJU_MACHINES=`echo $JUJU_MACHINES | sed 's/ /,/g'`

# change bundles variables
echo "INFO: Change variables in bundle..."
python3 "$my_dir/jinja2_render.py" <"${BUNDLE}" >"$WORKSPACE/bundle.yaml"

echo "INFO: Print bundle..."
cat "$WORKSPACE/bundle.yaml"

echo "INFO: Run bundle..."
juju deploy --debug $WORKSPACE/bundle.yaml --map-machines=existing

# workaround an issue with inability to install python-pip3 in lxd container
# due to incorrect handling of apt-get update in cloud-init the operation may silently fail
# and next calls to apt-get may fail
# call apt-get update manulayy to prevent this issue
if ! grep -q "lxd:" $WORKSPACE/bundle.yaml ; then
  exit
fi

# wait a bit while juju creates lxd machines in it's database
sleep 30
lxd_machines=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep "\/lxd\/" | awk '{print $1}'`
echo "INFO: lxd machines:"
echo $lxd_machines
for machine in $lxd_machines ; do
  wait_cmd_success 'juju ssh --proxy $machine "sudo apt-get update -y"'
done
# wait a bit while juju re-runs all failed hooks
sleep 120
