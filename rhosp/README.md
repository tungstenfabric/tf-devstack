# tf-devstack/rhosp

Bunch of scripts for deployment RHOSP on 4 VM (RHEL)

## Requirements

Red Hat account is needed for setting RHEL subscription.
KVM host that can run 4 instances with 2 virtual CPU, 8GB of RAM and 120 GB of disk space

## Limitations

Only RHOSP13 over Red Hat Enterprise Linux 7.7

## Options

There are 2 providers for deployment:

1) OpenStack cloud (default) - for CICD deployments (VEXX cloud does node provisioning)
2) KVM - deployment over KVM hypervisor (classic tripleO case, undercloud ironic does node provisioning)
3) AWS (todo)

## OpenStack installation

1. Install openstack CLI and setup authorization for OpenStack cloud.
1. Check that you have jq installed.
1. git clone <https://github.com/tungstenfabric/tf-devstack.git>
1. cd tf-devstack/rhosp
1. ./providers/openstack/create_env.sh it will create VMs and environment file rhosp-environment.sh
1. Copy directory tf-devstack and file rhosp-environment.sh to undercloud node
1. Login into undercloud (all other steps must be run there)
1. export PROVIDER=openstack
1. export RHEL_USER=...
1. export RHEL_PASSWORD=...
1. ./create_env.sh
1. ./run.sh

run.sh without parameters will do all the stages sequentially.
Also you can deploy stage by stage:

Stage by stage order

- Run ./run.sh undercloud. This stage deploys undercloud.
- Run ./run.sh overcloud. This stage provisions overcloud nodes
- Run ./run.sh tf. This stage deploys overcloud

## KVM installation

All steps must be done on kvm host.

KVM prerequisites:

- Enable hugepages. Update param GRUB_CMDLINE_LINUX in /etc/default/grub with `intel_iommu=on default_hugepagesz=1G hugepagesz=1G hugepages=118`. Exact value depends on your host RAM.
- Add firewall rules if applicable `ufw allow from 10.0.0.0/8 ; ufw allow from 172.0.0.0/8 ufw allow from 192.168.0.0/16`
- Install specific version of vbmc tool with `pip install "virtualbmc==1.5.0"`
- Upload base RHEL images to images pool (rhel-8.2-x86_64-kvm.qcow2 for rhosp16 and rhel-server-7.9-x86_64-kvm.qcow2 for rhosp13. For reference please see file [a relative link]providers/kvm/01_create_env.sh)

If You are going to deploy multiple environments on single libvirt/kvm host - You shoud export variable DEPLOY_POSTFIX.
It sets management network as `192.168.${DEPLOY_POSTFIX}` and provider network as `192.168.${DEPLOY_POSTFIX_INC}`.
Also, note that mac addresses are based on `DEPLOY_POSTFIX`, as in `00:16:00:00:${DEPLOY_POSTFIX}:02`.
DEPLOY_POSTFIX_INC equals DEPLOY_POSTFIX_INC + 1.

1. Setup KVM host
1. Login to KVM host
1. git clone <https://github.com/tungstenfabric/tf-devstack.git>
1. cd tf-devstack/rhosp
1. edit file config/env_kvm.sh (set correct ssh keys, BASE_IMAGE, etc)
1. export PROVIDER=kvm
1. export DEPLOY_POSTFIX=20
1. export RHEL_USER=...
1. export RHEL_PASSWORD=...
1. ./create_env.sh
1. ./run.sh

run.sh without parameters will do all the stages sequentially.
Also you can deploy stage by stage:

Stage by stage order

- Run ./create_env.sh. Creating of VM's and networks
- Run ./run.sh machines. Initial provisioning for undercloud node
- Run ./run.sh undercloud. This stage deploys undercloud.
- Run ./run.sh overcloud. This stage provisions overcloud nodes
- Run ./run.sh tf. This stage deploys overcloud
