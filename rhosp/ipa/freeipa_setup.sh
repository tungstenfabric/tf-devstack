#!/bin/bash -eux

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

sudo -E $my_dir/freeipa_setup_root.sh

# Precreate undercloud entry and generate OTP
otp=$(sudo novajoin-ipa-setup \
    --principal admin \
    --password "$AdminPassword" \
    --server `hostname -f` \
    --realm ${CLOUD_DOMAIN_NAME^^} \
    --domain ${CLOUD_DOMAIN_NAME} \
    --hostname ${UndercloudFQDN} \
    --precreate)

[ -n "$otp" ]
echo $otp > ~/undercloud_otp
