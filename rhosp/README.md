# tf-devstack/rhosp

Bunch of scripts for deployment RHOSP on 4 VM (RHEL) running inside qemu-kvm host (Ubuntu).

## Requirements

Bare metal KVM host with >8 CPU and >=32GB Memory
Red Hat account is needed for setting RHEL subscription.

## Limitations

Only RHOSP13 over Red Hat Enterprise Linux 7.7


## VEXX installation step by step guide

1) Create public network rhosp13-mgmt
2) Create private network rhosp13-prov
3) Create instance rhosp13-undercloud with primary network interface rhosp13-mgmt and secondary network interface rhosp13-prov (4 CPU, RAM 16Gb, HDD 30Gb)
4) Create instance rhosp13-overcloud-cont with only network interface rhosp13-prov (openstack controller, 4 CPU, RAM 16Gb, HDD 30Gb)
5) Create instance rhosp13-overcloud-compute with only network interface rhosp13-prov (openstack compute, 4 CPU, RAM 16Gb, HDD 30Gb)
6) Create instance rhosp13-overcloud-cont with only network interface rhosp13-prov (contrail controller, 4 CPU, RAM 16Gb, HDD 30Gb)
7) Assign floating ip on the instance rhosp13-undercloud and login to the instance
8) Disable port security on rhosp13-prov interfaces for all instances

All other step must be run on undercloud node

9) Clone tf-devstack repo git clone https://github.com/tungstenfabric/tf-devstack.git
10) Create file  $HOME/tf-devstack/rhosp/config/rhel-account.rc
export RHEL_USER=<login>
export RHEL_PASSWORD=<password>
export RHEL_POOL_ID=8a85f99c68b939320168c7f5b5b2461c

11) Put appropriate IP addresses and ssh credentials to file $HOME/tf-devstack/rhosp/config/env_vexx.sh

12) Run ./run.sh machines. This stage would create user stack and move repo tf-devstack to /home/stack and provision undercloud node
13) Run ./run.sh undercloud. This stage would deploy undercloud.
14) Run ./run.sh overcloud. This stage would provision overcloud nodes
15) Run ./run.sh tf. This stage would deploy overcloud


## KVM installation step by step guide

1) Setup KVM host
2) Create environment
3) Create file instackenv.json
4) Upload files to undercloud node: env_desc.sh, instackenv.json, undercloud/* overcloud/*

All other step must be run on undercloud node

5) Create file ~/rhel-account.rc
export RHEL_USER=<login>
export RHEL_PASSWORD=<password>
export RHEL_POOL_ID=8a85f99c68b939320168c7f5b5b2461c

6) cd undercloud and run scripts one by one

7) cd overcloud and run scripts one by one

Known issues

Sometimes node introspection doesn't work properly because nodes have *down* status in vbmc list.
Solution:
run vbmc start <node> on the KVM host for all the nodes and repeat node introspection on undercloud.
