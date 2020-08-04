# JuJu deployer

JuJu deployer provides JuJu-based deployment for TF with OpenStack or Kubernetes on Ubuntu.

## Hardware and software requirements

Recommended:

- instance with 8 virtual CPU, 16 GB of RAM and 120 GB of disk space to deploy all-in-one
- Ubuntu 18.04

## Quick start on an AWS instances on base of Kubernetes (all-in-one)

1. Launch new AWS instance.

- Ubuntu 18.04 (x86_64) - with Updates HVM
- c5.2xlarge instance type
- 120 GiB disk Storage

2. Set environment variables:

(optionally - these parameters are set by default)

``` bash
export ORCHESTRATOR='kubernetes'  # by default
export CLOUD='local'  # by default
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

2. Clone this repository and run the startup script:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/run.sh
```

## Quick start on an your own instances on base of Openstack

1. Launch 6 nodes:

- instance with 2 virtual CPU, 16 GB of RAM and 300 GB of disk space to deploy JuJu-controller, heat, contrail
- instance with 4 virtual CPU, 8 GB of RAM and 40 GB of disk space to deploy glance, nova-compute
- instance with 4 virtual CPU, 8 GB of RAM and 40 GB of disk space to deploy keystone
- instance with 2 virtual CPU, 8 GB of RAM and 40 GB of disk space to deploy nova-cloud-controller
- instance with 2 virtual CPU, 16 GB of RAM and 300 GB of disk space to deploy neutron
- instance with 2 virtual CPU, 8 GB of RAM and 40 GB of disk space to deploy openstack-dashboard, mysql, rabbit

- Ubuntu 18.04

Open ports 22, 17070 and 37017

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
export CLOUD='manual'
export CONTROLLER_NODES=*access ips of the rest 5 nodes*  # you should specify exactly 5 nodes for manual deployment.
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
- Five servers preconfigured for boot using IPMI.

1. Set environment variables:


``` bash
# Mandatory. List of IP addresses IPMI of servers. Example:
export IPMI_IPS="192.168.51.20 192.168.51.21 192.168.51.22 192.168.51.23 192.168.51.24" # IPMI IP adresses
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

## Quick start on an AWS instances on base of Kubernetes and Openstack (all-in-one)

1. Launch new AWS instance.

- Ubuntu 18.04 (x86_64) - with Updates HVM
- t3.2xlarge instance type
- 200 GiB disk Storage

2. Set environment variables:

``` bash
export ORCHESTRATOR='all'
export CLOUD='local'  # by default
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
export CLOUD='local'  # by default, another options are 'manual' and 'aws'
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

Juju is deployed on Ubuntu18 by default.
You can select Ubuntu 16 with environment variables before installation.

``` bash
export UBUNTU_SERIES=${UBUNTU_SERIES:-xenial}
./run.sh
```

## Environment variables

Environment variable list:

- UBUNTU_SERIES - version of ubuntu, bionic by default
- CONTAINER_REGISTRY - by default "opencontrailnightly"
- CONTRAIL_CONTAINER_TAG - by default "master-latest"
- CONTRAIL_DEPLOYER_CONTAINER_TAG - by default equal to CONTRAIL_CONTAINER_TAG
- JUJU_REPO - path to contrail-charms, "$PWD/contrail-charms" by default
- ORCHESTRATOR - orchestrator for deployment, "kubernetes" (default), "openstack" and "all" are supported
- CLOUD - cloud for juju deployment, "aws" and "local" are supported, "local" by default
- DATA_NETWORK - network for data traffic of workload and for control traffic between compute nodes and control services. May be set as cidr or physical interface. Optional.

## Known Issues

- For CentOS Linux only. If the vrouter agent does not start after installation, this is probably due to an outdated version of the Linux kernel. Update your system kernel to the latest version (yum update -y) and reboot your machine
