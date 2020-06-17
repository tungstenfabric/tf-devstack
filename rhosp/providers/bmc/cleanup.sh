#!/bin/bash -x


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $HOME/rhosp-environment.sh

ssh stack@${mgmt_ip} << 'EOF'
sudo subscription-manager unregister
source stackrc
servers=$(openstack server list -c Networks -f value | awk -F '=' '{print $NF}')
for server in $servers; do 
  ssh -T heat-admin@${server} "sudo subscription-manager unregister"
done
EOF

rm -rf "$HOME/rhosp-environment.sh"  "$HOME/.tf"
