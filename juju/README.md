# JuJu deployer

JuJu deployer provides JuJu-based deployment for TF with OpenStack or Kubernetes on Ubuntu.

## Hardware and software requirements

Recommended:
- instance with 8 virtual CPU, 16 GB of RAM and 120 GB of disk space to deploy all-in-one
- Ubuntu 18.04

## Quick start on an AWS instances on base of Kubernetes (all-in-one)

1. Launch new AWS instance.

1. Steps:
- Ubuntu 18.04 (x86_64) - with Updates HVM
- c5.2xlarge instance type
- 120 GiB disk Storage

2. Set environment variables:

(optionally - these parameters are set by default)

```
export ORCHESTRATOR='kubernetes'  # by default
export CLOUD='local'  # by default
```

3. Clone this repository and run the startup script:

```
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/startup.sh
```

4. Wait about 30-60 minutes to complete the deployment.


## Quick start on an AWS instances on base of Openstack

1. Set environment variables:
```
export ORCHESTRATOR='openstack'
export CLOUD='aws'
export AWS_ACCESS_KEY=*aws_access_key*
export AWS_SECRET_KEY=*aws_secret_key*
```

2. Clone this repository and run the startup script:
```
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/startup.sh
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


2. Make sure that juju-controller node has access to all other nodes.

On JuJu-controller node:
```
ssh-keygen -t rsa
```

Copy created public key
```
cat ~/.ssh/id_rsa.pub
```
and add it to ~/.ssh/authorized_keys on **all** other nodes.

3. On JuJu-controller node set environment variables:
```
export ORCHESTRATOR='openstack'
export CLOUD='manual'
export CONTROLLER_NODES=*access ips of 5 nodes*  # you should specify exactly 5 nodes for manual deployment.
```

4. Clone this repository and run the startup script:
```
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/startup.sh
```

## Partial installations

1. You should set SKIP_JUJU_BOOTSTRAP to **true** if Juju is already installed on your system, and there is already running JuJu controller.

2. You should set SKIP_JUJU_ADD_MACHINES to **true** if all machines are already added to the JuJu model.

3. You can set SKIP_ORCHESTRATOR_DEPLOYMENT to **true** if you have already deployed orchestrator earlier.

4. You can set SKIP_CONTRAIL_DEPLOYMENT to **true** if you don't want to deploy Contrail, but orchestrator only (openstack or kubernetes). You would be able to deploy Contrail later setting SKIP_CONTRAIL_DEPLOYMENT to **false** and SKIP_JUJU_BOOTSTRAP to **true**.


## Installation configuration

Juju is deployed on Ubuntu18 by default.
You can select Ubuntu 16 with environment variables before installation.

```
export UBUNTU_SERIES=${UBUNTU_SERIES:-xenial}
./startup.sh
```

## Environment variables
Environment variable list:
- UBUNTU_SERIES - version of ubuntu, bionic by default
- CONTAINER_REGISTRY - by default "opencontrailnightly"
- CONTRAIL_CONTAINER_TAG - by default "master-latest"
- JUJU_REPO - path to contrail-charms, "$PWD/contrail-charms" by default
- ORCHESTRATOR - orchestrator for deployment, "openstack" and "kubernetes" (default) are supported
- CLOUD - cloud for juju deployment, "aws" and "local" are supported, "local" by default
- SKIP_JUJU_BOOTSTRAP - skip installation, setup of JuJu, bootstrap JuJu controller, false by default
- SKIP_JUJU_ADD_MACHINES - skip adding machines if they are ready, false by default
- SKIP_ORCHESTRATOR_DEPLOYMENT - skip deployment of orchestrator (openstack or kubernetes), false by default
- SKIP_CONTRAIL_DEPLOYMENT - skip deployment of contrail, false by default
