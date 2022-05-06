#!/bin/bash -eux

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

[ -n "$UndercloudFQDN" ] || {
    echo "ERROR: UndercloudFQDN env variable must be set"
    exit 1
}

domain=${domain:-$(hostname -d)}
export CLOUD_DOMAIN_NAME=${CLOUD_DOMAIN_NAME:-"${domain}"}

sudo -E $my_dir/../../contrib/ipa/freeipa_setup_root.sh

# Precreate undercloud entry and generate OTP
novajoin-ipa-setup \
    --principal admin \
    --password "$AdminPassword" \
    --server `hostname -f` \
    --realm ${CLOUD_DOMAIN_NAME^^} \
    --domain ${CLOUD_DOMAIN_NAME} \
    --hostname ${UndercloudFQDN} \
    --otp-file ~/undercloud_otp \
    --precreate
