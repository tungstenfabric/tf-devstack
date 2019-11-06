#!/bin/bash

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

# parameters
BUNDLE=${BUNDLE:-} # may be template, would be rendered by jinja

# get list of machines to supply to bundle template, because machine indexes can change
JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
export MACHINES=`echo $JUJU_MACHINES | sed 's/ /,/g'`

# change bundles variables
echo "INFO: Change variables in bundle..."
python3 "$my_dir/jinja2_render.py" <"${BUNDLE}" >"$WORKSPACE/bundle.yaml"

juju deploy $WORKSPACE/bundle.yaml --map-machines=existing
