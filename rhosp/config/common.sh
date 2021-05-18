#!/bin/bash

export RHEL_POOL_ID=${RHEL_POOL_ID}
[ -n "$RHEL_POOL_ID" ] || RHEL_POOL_ID='8a85f999759ed5b40175b8b101f4632d'

state="$(set +o)"
[[ "$-" =~ e ]] && state+="; set -e"
set +x
export RHEL_PASSWORD=$RHEL_PASSWORD
export RHEL_USER=$RHEL_USER
eval "$state"

