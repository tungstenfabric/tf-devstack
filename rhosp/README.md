# tf-devstack/rhosp

Bunch of scripts for deployment RHOSP on 4 VM (RHEL) running inside qemu-kvm host (Ubuntu).

### Requirements:
Bare metal KVM host with >8 CPU and >=32GB Memory
Red Hat account is needed for setting RHEL subscription.

### Limitations:
Only RHOSP13 over Red Hat Enterprise Linux

### Files descriptions

run.sh                                    - Full tripleo deployment start script
kvm-host/00_provision_kvm_host.sh             - Initial provisioning for KVM host
kvm-host/01_create_env.sh                     - creating VMs, networks and setup vbmc
kvm-host/02_collecting_node_information.sh    - creating file instackenv.json for overcloud node introspection
kvm-host/clean_env.sh                         - cleanup environment
kvm-host/env.sh                               - file for setting variables
kvm-host/rhel-account.rc                      - file with RHEL credentials
kvm-host/virsh_functions                      - bash functions for managing libvirt
README.md                                     - you are here

undercloud/00_provision.sh                    - undercloud node provisioning
undercloud/01_deploy_as_root.sh               - deploy undercloud step 1
undercloud/02_deploy_as_stack.sh              - deploy undercloud step 2
undercloud.conf.template

overcloud/01_extract_overcloud_images.sh                 - unpacking overcloud images for introspection
overcloud/02_manage_overcloud_flavors.sh                 - creating flavors
overcloud/03_node_introspection.sh                       - overcloud node introspection via IPMI (vbmc)
overcloud/04_prepare_heat_templates.sh                   - preparing tripleo heat templates
overcloud/05_prepare_containers.sh                       - preparing docker containers
overcloud/06_deploy_overcloud.sh                         - deployment overcloud
overcloud/contrail-parameters.yaml.template
overcloud/environment-rhel-registration.yaml.template
overcloud/misc_opts.yaml.template
overcloud/roles_data_contrail_aio.yaml

### Installation with run.sh

1) Put appropriate variables in kvm-host/env.sh

2) Create file kvm-host/rhel-account.rc
export RHEL_USER=<login>
export RHEL_PASSWORD=<password>
export RHEL_POOL_ID=8a85f99c68b939320168c7f5b5b2461c

3) Run run.sh



### Installation step by step guide

1) Setup KVM host
2) Create environment
3) Create file instackenv.json
4) Upload files to undercloud node: kvm-host/env.sh, kvm-host/instackenv.json, undercloud/* overcloud/*

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



