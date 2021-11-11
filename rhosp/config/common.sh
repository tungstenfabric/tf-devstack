#!/bin/bash

[ -n "$RHEL_POOL_ID" ] || RHEL_POOL_ID='8a85f99b77b0c6850177ceb51fdd237b'
export RHEL_POOL_ID=$RHEL_POOL_ID

state="$(set +o)"
[[ "$-" =~ e ]] && state+="; set -e"
set +x
export RHEL_PASSWORD=$RHEL_PASSWORD
export RHEL_USER=$RHEL_USER
eval "$state"
