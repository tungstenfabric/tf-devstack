#!/bin/bash


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


if [[ `whoami` !=  'stack' ]]; then
   echo "This script must be run by user 'stack'"
   exit 1
fi

if [ -f /home/stack/rhosp-environment.sh ]; then
   source /home/stack/rhosp-environment.sh
else
   echo "File /home/stack/rhosp-environment.sh not found"
   exit
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


if [ ! -d /home/stack/.ssh ]; then
   mkdir -p /home/stack/.ssh
fi

chmod 700 /home/stack/.ssh
# Generate key-pair
ssh-keygen -b 2048 -t rsa -f /tmp/sshkey -q -N ""

# ssh config to do not check host keys and avoid garbadge in known hosts files
cat <<EOF >/home/stack/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF
chown stack:stack /home/stack/.ssh/config
chmod 644 /home/stack/.ssh/config

cd $my_dir
cat undercloud.conf.template | envsubst >/home/stack/undercloud.conf

openstack undercloud install

#Adding stack to group docker
sudo usermod -a -G docker stack

echo User 'stack' has been added to group 'docker'. Please relogin


