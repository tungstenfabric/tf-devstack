#!/bin/bash
#
# Used environment variables:
#
#   - Hostname
#   - FreeIPAIP
#   - DirectoryManagerPassword
#   - AdminPassword
#   - UndercloudFQDN
#   - HostsSecret
#   - ProvisioningCIDR: If set, it adds the given CIDR to the provisioning
#                       interface (which is hardcoded to eth1)
#   - FreeIPAExtraArgs: Additional parameters to be passed to FreeIPA script
#
set -eux

export Hostname=${Hostname:-""}
export FreeIPAIP=${FreeIPAIP:-""}
export DirectoryManagerPassword=${DirectoryManagerPassword:-""}
export AdminPassword=${AdminPassword:-""}
export UndercloudFQDN=${UndercloudFQDN:-""}
export HostsSecret=${HostsSecret:-""}
export ProvisioningCIDR=${ProvisioningCIDR:-""}
export FreeIPAExtraArgs=${FreeIPAExtraArgs:-""}

source /etc/os-release

# RHEL8.0 does not have epel yet
if [[ $VERSION_ID == 8* ]]; then
    PKGS="ipa-server ipa-server-dns rng-tools git"
else
    PKGS="ipa-server ipa-server-dns epel-release rng-tools mod_nss git haveged"
fi

yum -q -y remove openstack-dashboard
yum update -y
yum -q install -y $PKGS

# Set iptables rules
cat << EOF > freeipa-iptables-rules.txt
# Firewall configuration written by system-config-firewall
# Manual customization of this file is not recommended.
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT
#TCP ports for FreeIPA
-A INPUT -m state --state NEW -m tcp -p tcp --dport 80 -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 443  -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 389 -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 636 -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 88  -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 464  -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 53  -j ACCEPT
#UDP ports for FreeIPA
-A INPUT -m state --state NEW -m udp -p udp --dport 88 -j ACCEPT
-A INPUT -m state --state NEW -m udp -p udp --dport 464 -j ACCEPT
-A INPUT -m state --state NEW -m udp -p udp --dport 123 -j ACCEPT
-A INPUT -m state --state NEW -m udp -p udp --dport 53 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT
EOF

iptables-restore < freeipa-iptables-rules.txt

# Entropy generation; otherwise, ipa-server-install will lag.
chkconfig haveged on
systemctl start haveged

# Remove conflicting httpd configuration
rm -f /etc/httpd/conf.d/ssl.conf

# Set up FreeIPA
ipa-server-install -U -r `hostname -d|tr "[a-z]" "[A-Z]"` \
                   -p $DirectoryManagerPassword -a $AdminPassword \
                   --hostname `hostname -f` \
                   --ip-address=$FreeIPAIP \
                   --setup-dns --auto-forwarders --auto-reverse $FreeIPAExtraArgs

# Authenticate
echo $AdminPassword | kinit admin

# Verify we have TGT
klist

# Precreate undercloud entry and generate OTP
otp=$(/usr/lib/python2.7/site-packages/usr/libexec/novajoin-ipa-setup \
    --principal admin \
    --password "$AdminPassword" \
    --server `hostname -f` \
    --realm ${CLOUD_DOMAIN_NAME^^} \
    --domain ${CLOUD_DOMAIN_NAME} \
    --hostname ${UndercloudFQDN} \
    --precreate)

echo $otp > ~/undercloud_otp

if [ "$?" = '1' ]; then
    exit 1
fi
