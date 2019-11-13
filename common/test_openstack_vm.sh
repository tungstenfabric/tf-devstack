#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"
source "$my_dir/functions.sh"
source "$my_dir/openrc"

TEST_SUBNET_CIDR="${TEST_SUBNET_CIDR:-172.23.0.0/24}"
TEST_IMAGE_NAME="${TEST_IMAGE_NAME:-Cirros 0.3.5 64-bit}"

function cleanup() {
  openstack server delete tf-devstack-testvm --wait || :
  openstack flavor delete m1.micro || :
  openstack security group delete allow_ssh || :
  openstack subnet delete tf-devstack-subnet-test || :
  openstack network delete tf-devstack-test || :
}

# Clean up proactively in case previous attempt failed
cleanup

# Set up
openstack network create tf-devstack-test
openstack subnet create --subnet-range "$TEST_SUBNET_CIDR" --network tf-devstack-test tf-devstack-subnet-test
openstack security group create allow_ssh
openstack security group rule create --dst-port 22 --protocol tcp allow_ssh
openstack flavor create --ram 64 --disk 1 --vcpus 1 m1.micro

# Deploy
openstack server create --image "$TEST_IMAGE_NAME" --flavor m1.micro --nic net-id=tf-devstack-test --security-group allow_ssh --wait tf-devstack-testvm

# Tear down
cleanup
