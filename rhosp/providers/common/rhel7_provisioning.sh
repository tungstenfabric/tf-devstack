sudo yum update -y

package="ntp wget yum-utils vim iproute jq curl bind-utils bridge-utils net-tools python-heat-agent* python-virtualenv python-docker python27-python-pip"
[[ "$ENABLE_TLS" != 'ipa' ]] || packages+=" ipa-client python-novajoin"

sudo yum install -y $package

sudo chkconfig ntpd on
sudo service ntpd restart

# install pyton3 after pip
sudo yum install -y python3 python3-pyyaml python33-python-six rh-python36-python-six
