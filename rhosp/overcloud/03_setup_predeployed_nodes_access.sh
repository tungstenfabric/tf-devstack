#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd
source stackrc
source rhosp-environment.sh
source $my_dir/../../common/common.sh

export OVERCLOUD_HOSTS="${overcloud_cont_prov_ip} ${overcloud_compute_prov_ip} ${overcloud_ctrlcont_prov_ip}"
/usr/share/openstack-tripleo-heat-templates/deployed-server/scripts/enable-ssh-admin.sh >/dev/null
