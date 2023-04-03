#!/bin/bash

# Subscription Name:   Red Hat OpenStack Platform, Self-Support (4 Sockets, NFR, Partner Only)
# Available:           Unlimited
# Entitlement Type:    Virtual

# for 'physical' type we have to define another pool id

[ -n "$RHEL_POOL_ID" ] || RHEL_POOL_ID='2c948b68859c15590185badd1e292e03'
export RHEL_POOL_ID=$RHEL_POOL_ID

state="$(set +o)"
[[ "$-" =~ e ]] && state+="; set -e"
set +x
export RHEL_PASSWORD=$RHEL_PASSWORD
export RHEL_USER=$RHEL_USER
eval "$state"
