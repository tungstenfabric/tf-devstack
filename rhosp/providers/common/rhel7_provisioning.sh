sudo yum update -y

packages="ntp wget yum-utils vim iproute jq curl bind-utils bridge-utils net-tools python-heat-agent* python-docker python3"
[[ "$ENABLE_TLS" != 'ipa' ]] || {
  packages+=" ipa-client python-novajoin openssl-perl ca-certificates"
  # rhosp13 overcloud images have installed the following packages that
  # create groups qemu, rabbitmq, mysql.
  # Theses users are needed for certs puppets.
  packages+=" rabbitmq-server libvirt mariadb-server"
}

sudo yum install -y $packages

sudo chkconfig ntpd on
sudo service ntpd restart
