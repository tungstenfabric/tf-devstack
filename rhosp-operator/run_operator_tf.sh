#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

deploy_operator_file="deploy_operator.sh"

export overcloud_node_ip=$overcloud_cont_prov_ip
export cakey=$(echo "$SSL_CAKEY" | base64 -w 0)
export cabundle=$(echo "$SSL_CACERT" | base64 -w 0)

cd
source rhosp-environment.sh
CONTROLLER_NODES="$(echo $overcloud_ctrlcont_prov_ip | tr ',' ' ')"

$my_dir/../common/jinja2_render.py < $my_dir/${deploy_operator_file}.j2 >/tmp/${deploy_operator_file}
sudo chmod 755 /tmp/${deploy_operator_file}

ctrlcont_node=$(echo $overcloud_ctrlcont_prov_ip | cut -d, -f1)
scp $ssh_opts /tmp/${deploy_operator_file} $SSH_USER@$ctrlcont_node:
# ctrlcont node should have access to other ctrcont nodes
scp $ssh_opts $HOME/.ssh/id_rsa $SSH_USER@$ctrlcont_node:/home/$SSH_USER/.ssh/
ssh $ssh_opts $SSH_USER@$ctrlcont_node ./deploy_operator.sh
