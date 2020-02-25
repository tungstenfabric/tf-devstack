# tf-devstack/rhosp

Bunch of scripts for deployment RHOSP on 4 VM (RHEL)


## Requirements

Red Hat account is needed for setting RHEL subscription.

## Limitations

Only RHOSP13 over Red Hat Enterprise Linux 7.7

## Options

There are 2 providers for deployment:
1) VEXX cloud (default) - for CICD deployments (VEXX cloud does node provisioning)
2) KVM - deployment over KVM hypervisor (classic tripleO case, undercloud ironic does node provisioning)
3) AWS (todo)

## VEXX installation

1. Install openstack CLI and setup authorization for VEXX cloud.
1. git clone https://github.com/tungstenfabric/tf-devstack.git
1. cd tf-devstack/rhosp
1. ./providers/vexx/create_env.sh it will create VMs and environment file ~/rhosp-environment.sh
1. Copy directory ~/tf-devstack and file ~/rhosp-environment.sh to undercloud node
1. Login into undercloud (all other steps must be run there)
1. export PROVIDER=vexx
1. export RHEL_USER=...
1. export RHEL_PASSWORD=...
1. ./run.sh

run.sh without parameters will do all the stages sequentially.
Also you can deploy stage by stage:

Stage by stage order
 - Run ./run.sh undercloud. This stage deploys undercloud.
 - Run ./run.sh overcloud. This stage provisions overcloud nodes
 - Run ./run.sh tf. This stage deploys overcloud


## KVM installation
All steps must be done on kvm host

1. Setup KVM host
1. Login to KVM host
1. git clone https://github.com/tungstenfabric/tf-devstack.git
1. cd tf-devstack/rhosp
1. edit file config/env_kvm.sh (set correct ssh keys, BASE_IMAGE, etc)
1. export PROVIDER=kvm
1. export RHEL_USER=...
1. export RHEL_PASSWORD=...
1. ./run.sh

run.sh without parameters will do all the stages sequentially.
Also you can deploy stage by stage:

Stage by stage order
 - Run ./run.sh kvm. This stage creates VMs and networks
 - Run ./run.sh machines. Initial provisioning for undercloud node
 - Run ./run.sh undercloud. This stage deploys undercloud.
 - Run ./run.sh overcloud. This stage provisions overcloud nodes
 - Run ./run.sh tf. This stage deploys overcloud

