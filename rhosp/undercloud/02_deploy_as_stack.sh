#!/bin/bash

if [[ `whoami` !=  'stack' ]]; then
   echo "This script must be run by user 'stack'" 
   exit 1
fi

if [ -f ~/rhel-account.rc ]; then
   source ~/rhel-account.rc
else
   echo "File ~/rhel-account not found"
   exit    
fi

if [ -f ~/env_desc.sh ]; then
   source ~/env_desc.sh
else
   echo "File ~/env_desc.sh not found"
   exit    
fi

mkdir -p /home/stack/.ssh
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
chmod 600 /home/stack/.ssh/config

cat undercloud.conf.template | envsubst >/home/stack/undercloud.conf

openstack undercloud install

#Adding stack to group docker
sudo usermod -a -G docker stack

echo User 'stack' has been added to group 'docker'. Please relogin 


