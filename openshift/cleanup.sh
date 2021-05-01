#!/bin/bash -e

if [[ $PROVIDER == "aws" ]]; then
    ./openshift-install destroy cluster --dir=$INSTALL_DIR
fi