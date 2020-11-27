sudo yum update -y

package="ntp wget yum-utils vim iproute jq curl bind-utils bridge-utils net-tools python-heat-agent* python-docker python3"
[[ "$ENABLE_TLS" != 'ipa' ]] || packages+=" ipa-client python-novajoin openssl-perl ca-certificates"

sudo yum install -y $package

sudo chkconfig ntpd on
sudo service ntpd restart
