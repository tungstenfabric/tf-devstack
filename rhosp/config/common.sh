#!/bin/bash

# Subscription Name:   Red Hat OpenStack Platform, Self-Support (4 Sockets, NFR, Partner Only)
# Available:           Unlimited
# Entitlement Type:    Virtual

# for 'physical' type we have to define another pool id

[ -n "$RHEL_POOL_ID" ] || RHEL_POOL_ID='8a85f99b7ed9423e017ed9f30a062766'
export RHEL_POOL_ID=$RHEL_POOL_ID

state="$(set +o)"
[[ "$-" =~ e ]] && state+="; set -e"
set +x
export RHEL_PASSWORD=$RHEL_PASSWORD
export RHEL_USER=$RHEL_USER
eval "$state"
