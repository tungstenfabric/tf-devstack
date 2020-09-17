# JuJu deployer

JuJu deployer provides JuJu-based deployment for TF with OpenStack or Kubernetes on Ubuntu.

## Hardware and software requirements

Recommended:

- instance with 8 virtual CPU, 16 GB of RAM for kubernetes and 32 GB of RAM for OpenStack, 120 GB of disk space to deploy all-in-one
- Ubuntu 18.04

## Quick start on a local instance on base of Kubernetes (all-in-one)

1. Launch new instance.

- Ubuntu 18.04 (x86_64) - with Updates HVM
- 8 virtual CPU, 16 GB of RAM
- 120 GiB disk Storage

2. Set environment variables:

(optionally - these parameters are set by default)

``` bash
export ORCHESTRATOR='kubernetes'  # by default
export CLOUD='manual'  # by default
```

3. Clone this repository and run the startup script:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/run.sh
```

4. Wait about 30-60 minutes to complete the deployment.

## Quick start on an AWS instances on base of Openstack

1. Set environment variables:

``` bash
export ORCHESTRATOR='openstack'
export CLOUD='aws'
export AWS_ACCESS_KEY=*aws_access_key*
export AWS_SECRET_KEY=*aws_secret_key*
```

2. (optional) Set Controller and Agent nodes configuration.
``` bash
export CONTROLLER_NODES='C1 C2 C3'
export AGENT_NODES='A4 A5'
```

You may use any symbols separated by spaces, the same symbols will point to the same machines.

For example:
``` bash
export CONTROLLER_NODES='C1 C2 C3'
export AGENT_NODES='A4 A5'
```
5 machines would be raised - 3 for controllers, 2 for agents

``` bash
export CONTROLLER_NODES='M1 M2 M3'
export AGENT_NODES='M1 M2'
```
3 machines would be raised - controllers would be situated on all af them and agents on two of them.

If nothing is imported for CONTROLLER_NODES and AGENT_NODES, it will raise one machine with all-in-one setup.

3. Clone this repository and run the startup script:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/run.sh
```

## Quick start on an your own instances on base of Openstack

1. Launch nodes.

Recommended:

- instance with 8 virtual CPU, 16 GB of RAM and 120 GB of disk space for controller nodes
- instance with 4 virtual CPU, 8 GB of RAM and 80 GB of disk space for agent nodes
- Ubuntu 18.04

Open ports 22, 17070 and 37017 between them

2. Make sure that juju-controller node has access to all other nodes.

On JuJu-controller node:

``` bash
ssh-keygen -t rsa
```

Copy created public key

``` bash
cat ~/.ssh/id_rsa.pub
```

and add it to ~/.ssh/authorized_keys on **all** other nodes.

3. On JuJu-controller node set environment variables:

``` bash
export ORCHESTRATOR='openstack'
export CLOUD='manual'  # by default
export CONTROLLER_NODES=*access ips of the machines you prepared for controller nodes* 
export AGENT_NODES=*access ips of the machines you prepared for agent nodes* 
```

4. Clone this repository and run the startup script:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/run.sh
```

## Quick start on an MAAS on base of Openstack

1. Set environment variables:

``` bash
export ORCHESTRATOR='openstack'
export CLOUD='maas'
export MAAS_ENDPOINT="*maas_endpoint_url*"
export MAAS_API_KEY="*maas_user_api_key*"
```
2. For deploying with the high availability need seven virtual addresses. These IP addresses must be on the same MAAS subnet where the applications will be deployed, do not overlap with the DHCP range or be reserved. Specify the first IP of seven range addresses in the CIDR notation (the following six IP also will be used) or all seven VIP separated by spaces.
Example:

``` bash
export VIRTUAL_IPS="192.168.51.201/24"
```
or

``` bash
export VIRTUAL_IPS="192.168.51.201 192.168.51.211 192.168.51.214 192.168.51.215 192.168.51.217 192.168.51.228 192.168.51.230"
```

3. Clone this repository and run the startup script:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/run.sh
```

Quick Maas deployment for use with Juju

Prerequisites:

- A subnet of at least 500 IP addresses with the Internet connectivity without using DHCP.
- Host for MAAS system: 8GiB RAM, 2 CPUs, 1 NIC, 1 x 40GiB storage.
- Six servers preconfigured for boot using IPMI.

1. Set environment variables:


``` bash
# Mandatory. List of IP addresses IPMI of servers. Example:
export IPMI_IPS="192.168.51.20 192.168.51.21 192.168.51.22 192.168.51.23 192.168.51.24 192.168.51.25" # IPMI IP adresses
# Optional
IPMI_POWER_DRIVER (Default: "LAN_2_0") # "LAN_2_0" for IPMI v2.0 or "LAN" for IPMI v1.5
IPMI_USER (Default: "ADMIN")
IPMI_PASS (Default: "ADMIN")
MAAS_ADMIN (Default: "admin")
MAAS_PASS (Default: "admin")
MAAS_ADMIN_MAIL (Default: "admin@maas.tld")
UPSTREAM_DNS (Default: "8.8.8.8")
```

2. Clone this repository and run the scripts:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/common/deploy_maas.sh
```

3. Use variables from script output for juju deployment on MAAS cloud.

``` bash
export MAAS_ENDPOINT="*maas_endpoint_url*"
export MAAS_API_KEY="*maas_user_api_key*"
export VIRTUAL_IPS="*ip_1 ip_2 ip_3 ip_4 ip_5 ip_6 ip_7*"
```

## Quick start on a local instance on base of Kubernetes and Openstack (all-in-one)

1. Launch new AWS instance.

- Ubuntu 18.04 (x86_64) - with Updates HVM
- t3.2xlarge instance type
- 200 GiB disk Storage

2. Set environment variables:

``` bash
export ORCHESTRATOR='all'
export CLOUD='manual'  # by default
```

3. Clone this repository and run the startup script:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/run.sh
```

4. Wait about 30-60 minutes to complete the deployment.

## Cleanup

1. Set environment variables:

``` bash
export CLOUD='manual'  # by default, another options are 'maas' and 'aws'
```

2. If you're using manual deployment

``` bash
export CONTROLLER_NODES=*access ips of the rest 5 nodes*
```

3. Run the cleanup script:

``` bash
tf-devstack/juju/cleanup.sh
```

## Installation configuration

You can select different Ubuntu version for deploy with environment variables before installation.
But this can be specified only for cases when your jumphost is not in a list of machines for setup.

``` bash
export UBUNTU_SERIES=xenial
./run.sh
```

## Environment variables

Environment variable list:

- UBUNTU_SERIES - version of ubuntu, by default it's equal to current host
- CONTAINER_REGISTRY - by default "opencontrailnightly"
- CONTRAIL_CONTAINER_TAG - by default "master-latest"
- CONTRAIL_DEPLOYER_CONTAINER_TAG - by default equal to CONTRAIL_CONTAINER_TAG
- JUJU_REPO - path to contrail-charms, "$PWD/contrail-charms" by default
- ORCHESTRATOR - orchestrator for deployment, "kubernetes" (default), "openstack" and "all" are supported
- CLOUD - cloud for juju deployment, "aws", "maas" and "manual" are supported, "manual" by default
- CONTROL_NETWORK - The CIDR of the control network (e.g. 192.168.0.0/24). This network will be used for Contrail endpoints. If not specified, default network will be used. Optional.
- DATA_NETWORK - network for data traffic of workload and for control traffic between compute nodes and control services. May be set as cidr or physical interface. Optional.

## Known Issues
