#!/bin/bash -e

[ "${DEBUG,,}" == "true" ] && set -x

if [[ $PROVIDER == "aws" ]]; then
    ./openshift-install destroy cluster --dir=$INSTALL_DIR
fi