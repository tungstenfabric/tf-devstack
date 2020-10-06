#!/bin/bash

export RHEL_POOL_ID=${RHEL_POOL_ID}
[ -n "$RHEL_POOL_ID" ] || RHEL_POOL_ID='8a85f99970453685017057d235142b3b'

state="$(set +o)"
[[ "$-" =~ e ]] && state+="; set -e"
set +x
export RHEL_PASSWORD=$RHEL_PASSWORD
export RHEL_USER=$RHEL_USER
eval "$state"

