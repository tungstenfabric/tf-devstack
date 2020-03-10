#!/bin/bash


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


if [ -f ~/rhosp-environment.sh ]; then
   source ~/rhosp-environment.sh
else
   echo "File ~/rhosp-environment.sh not found"
   exit
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


if [ ! -d ~/.ssh ]; then
   mkdir -p ~/.ssh
fi

chmod 700 ~/.ssh
# Generate key-pair
ssh-keygen -b 2048 -t rsa -f /tmp/sshkey -q -N ""

# ssh config to do not check host keys and avoid garbadge in known hosts files
cat <<EOF >~/.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF
chmod 644 ~/.ssh/config

cd $my_dir
export local_mtu=`ip link show $undercloud_local_interface | grep -o "mtu.*" | awk '{print $2}'`
cat undercloud.conf.template | envsubst >~/undercloud.conf

openstack undercloud install

#Adding user to group docker
user=$(whoami)
sudo usermod -a -G docker $user

echo User "$user" has been added to group "docker". Please relogin


