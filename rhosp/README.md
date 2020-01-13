# tf-devstack/rhosp

Bunch of scripts for deployment RHOSP on 4 VM (RHEL)


## Requirements

Red Hat account is needed for setting RHEL subscription.

## Limitations

Only RHOSP13 over Red Hat Enterprise Linux 7.7


## VEXX installation step by step guide

Create networks, instances and setup port security. It can be done with scripts from tf-devstack/rhosp/providers/vexx/
or manually
Script create_env.sh creates all network and instances and shows variables for deployment. You have to put these variables into the file
$HOME/tf-devstack/rhosp/config/env_vexx.sh before running run.sh


Manual steps (These steps can be done with openstack CLI or with Openstack Dashboard UI)
1) Create public network rhosp13-mgmt
2) Create private network rhosp13-prov
3) Create instance rhosp13-undercloud with primary network interface rhosp13-mgmt and secondary network interface rhosp13-prov (4 CPU, RAM 16Gb, HDD 30Gb)
4) Create instance rhosp13-overcloud-cont with only network interface rhosp13-prov (openstack controller, 4 CPU, RAM 16Gb, HDD 30Gb)
5) Create instance rhosp13-overcloud-compute with only network interface rhosp13-prov (openstack compute, 4 CPU, RAM 16Gb, HDD 30Gb)
6) Create instance rhosp13-overcloud-cont with only network interface rhosp13-prov (contrail controller, 4 CPU, RAM 16Gb, HDD 30Gb)
7) Assign floating ip on the instance rhosp13-undercloud and login to the instance
8) Disable port security on rhosp13-prov interfaces for all instances

All other steps must be run on undercloud node

9) Put private ssh key on undercloud instance. Undercloud need private ssh key to authorize on overcloud nodes.

10) Clone tf-devstack repo git clone https://github.com/tungstenfabric/tf-devstack.git
11) Define RHEL credential variables RHEL_USER and RHEL_PASSWORD
export RHEL_USER=<login>
export RHEL_PASSWORD=<password>

12) Put appropriate IP addresses and ssh credentials to file $HOME/tf-devstack/rhosp/config/env_vexx.sh

13) Run ./run.sh without options for full deployment or you can run it stage by stage

Stage by stage order
 - Run ./run.sh machines. This stage would create user stack and move repo tf-devstack to /home/stack and provision undercloud node
 - Run ./run.sh undercloud. This stage would deploy undercloud.
 - Run ./run.sh overcloud. This stage would provision overcloud nodes
 - Run ./run.sh tf. This stage would deploy overcloud


## KVM installation step by step guide

1) Setup KVM host
2) Create environment
3) Create file instackenv.json
4) Upload files to undercloud node: env_desc.sh, instackenv.json, undercloud/* overcloud/*

All other steps must be run on undercloud node

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
