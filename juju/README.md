# JuJu deployer

JuJu deployer provides JuJu-based deployment for TF with OpenStack or Kubernetes on Ubuntu.

## Hardware and software requirements

Recommended:
- instance with 2 virtual CPU, 4 GB of RAM and 10 GB of disk space to start juju-controller
- instance with 8 virtual CPU, 16 GB of RAM and 120 GB of disk space to deploy from charms

- Ubuntu 18.04

## Quick start on an AWS instances on base of Kubernetes (all-in-one)

1. Launch two new AWS instances.

Juju-controller instance
Steps:
- Ubuntu 18.04 (x86_64) - with Updates HVM
- t2.medium instance type
- 8 GiB disk Storage

Juju-deploy instance
Steps:
- Ubuntu 18.04  (x86_64) - with Updates HVM
- c5.2xlarge instance type
- 120 GiB disk Storage

2. Open on both instances security group TCP ports 22(ssh) and 17070.

3. Log into a juju-controller instance.
Generate key for ssh access:

```
ssh-keygen -t rsa
```

Copy public key to ~/.ssh/authorized_keys to **both** machines.

4. Set environmet variables:

```
export ORCHESTRATOR='kubernetes'
export CLOUD='manual'
CONTROLLER_NODES=*ip of machine on which
```

5. Clone this repository and run the startup script:

```
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/startup.sh
```

6. Wait about 30-60 minutes to complete the deployment.


## Quick start on an AWS instances on base of Openstack

1. Set environmet variables:
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

## Partial installations

1. You should set SKIP_JUJU_BOOTSTRAP to **true** if Juju is already installed on your system, and there is already running JuJu controller.

2. You should set SKIP_JUJU_ADD_MACHINES to **true** if all machines are already added to the JuJu model.

3. You can set SKIP_ORCHESTRATOR_DEPLOYMENT to **true** if you have already deployed orchestrator earlier.

4. You can set SKIP_DEPLOY_CONTRAIL to **true** if you don't want to deploy Contrail, but orchestrator only (openstack or kubernetes). You would be able to deploy Contrail later setting SKIP_DEPLOY_CONTRAIL to **false** and  SKIP_JUJU_BOOTSTRAP to **true**.


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
- ORCHESTRATOR - orchestrator for deployment, "openstack" (default) and "kubernetes" are supported
- CLOUD - cloud for juju deploy, "aws" and "manual" are supported, "aws" by default
- SKIP_JUJU_BOOTSTRAP - skip installation, setup of JuJu, bootstrap JuJu controller, false by default
- SKIP_JUJU_ADD_MACHINES - skip adding machines if they are ready, false by default
- SKIP_ORCHESTRATOR_DEPLOYMENT - skip deployment of orchestrator (openstack or kubernetes), false by default
- SKIP_CONTRAIL_DEPLOYMENT - skip deployment of contrail, false by default
