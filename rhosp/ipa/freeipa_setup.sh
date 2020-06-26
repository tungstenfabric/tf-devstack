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

if [ -f ~/freeipa-setup.env ]; then
    source ~/freeipa-setup.env
elif [ -f /tmp/freeipa-setup.env ]; then
    source /tmp/freeipa-setup.env
fi

export Hostname=${Hostname:-""}
export FreeIPAIP=${FreeIPAIP:-""}
export DirectoryManagerPassword=${DirectoryManagerPassword:-""}
export AdminPassword=${AdminPassword:-""}
export UndercloudFQDN=${UndercloudFQDN:-""}
export HostsSecret=${HostsSecret:-""}
export ProvisioningCIDR=${ProvisioningCIDR:-""}
export FreeIPAExtraArgs=${FreeIPAExtraArgs:-""}

if [ -n "$ProvisioningCIDR" ]; then
    # Add address to provisioning network interface
    ip link set dev eth1 up
    ip addr add $ProvisioningCIDR dev eth1
fi

# Set DNS servers
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf

yum -q -y remove openstack-dashboard

# Install the needed packages
# yum -q install -y yum-plugin-versionlock
# yum versionlock \
#   ipa-server-common-4.6.4-10* \
#   ipa-server-dns-4.6.4-10* \
#   ipa-client-4.6.4-10* \
#   pki-kra-10.5.9-13* \
#   pki-ca-10.5.9-13* \
#   pki-server-10.5.9-13*
# yum -q install -y \
#   pki-kra-10.5.9-13.el7_6.noarch \
#   pki-server-10.5.9-13.el7_6.noarch \
#   pki-ca-10.5.9-13.el7_6.noarch \
#   ipa-server-4.6.4-10.el7_6.3 \
#   ipa-server-dns-4.6.4-10.el7_6.3 \
#   epel-release rng-tools mod_nss git haveged
yum update -y
yum -q install -y epel-release rng-tools mod_nss git haveged ipa-server ipa-server-dns

# install complicated python deps for novajoin
# add OpenStack repositories for centos, for rhel it is added in images
if [[ "$ENVIRONMENT_OS" == 'rhel' ]] ; then
  [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] && yum-config-manager --enable rhelosp-rhel-7-server-opt
else
  tripeo_repos=`python -c "import requests;r = requests.get('https://trunk.rdoproject.org/centos7-${OPENSTACK_VERSION}/current'); print r.text " | grep python2-tripleo-repos | awk -F"href=\"" '{print $2}' | awk -F"\"" '{print $1}'`
  yum install -y https://trunk.rdoproject.org/centos7-${OPENSTACK_VERSION}/current/${tripeo_repos}
  tripleo-repos -b $OPENSTACK_VERSION current
  # in new centos a variable is introduced,
  # so it is needed to have it because  yum repos
  # started using it.
  if [[ ! -f  /etc/yum/vars/contentdir ]] ; then
    echo centos > /etc/yum/vars/contentdir
  fi
fi

# # install python deps for novajoin, but install instead from pip because we need 1.0.21
yum deplist python-novajoin | awk '/provider:/ {print $2}' | sort -u | xargs yum -y install

curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
python get-pip.py
pip install -q novajoin==1.0.21 oslo.policy==1.33.2

# # Prepare hostname
# hostnamectl set-hostname --static $Hostname

# echo $FreeIPAIP `hostname` | tee -a /etc/hosts

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

#                   --domain `hostname -f | cut -d '.' -f 2,3`

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
