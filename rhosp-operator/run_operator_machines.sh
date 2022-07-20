#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
operator_dir=$my_dir/../operator


# prepare environment
cd
source rhosp-environment.sh
export CONTROLLER_NODES="$(echo $overcloud_ctrlcont_prov_ip | tr ',' ' ')"
export AGENT_NODES="$( echo $overcloud_compute_prov_ip | tr ',' ' ')"
export OPENSTACK_CONTROLLER_NODES="$(echo $overcloud_cont_prov_ip | tr ',' ' ')"
if [[ -n "$IPA_NODES" ]] ; then
    # at this point if IPA_NODES are set, they are set to "small:1", reseting it to ips
    export IPA_NODES="$(echo $ipa_prov_ip | tr ',' ' ')"
    export DEPLOY_IPA_SERVER=false
fi
rm -rf $my_dir/../.git

$operator_dir/run.sh machines
