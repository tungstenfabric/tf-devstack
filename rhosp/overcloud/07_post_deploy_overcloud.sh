#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh
source $my_dir/../../common/common.sh
source $my_dir/../../common/functions.sh
source $my_dir/../providers/common/functions.sh
source $my_dir/../providers/common/common.sh

agent_node=$(get_first_agent_node)
check_nodedata $agent_node $SSH_USER_OVERCLOUD
