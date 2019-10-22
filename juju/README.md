## Hardware and software requirements

Recommended:
- instance with 2 virtual CPU, 4 GB of RAM and 10 GB of disk space to start juju-controller
- instance with 8 virtual CPU, 16 GB of RAM and 120 GB of disk space to deploy from charms

- Ubuntu 18.04

## Quick start on an AWS instances

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

4. Clone this repository and run the startup script:

```
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/juju/startup.sh
```

5. Wait about 30-60 minutes to complete the deployment.

## Installation configuration

Juju is deployed on Ubuntu18 by default.
You can select Ubuntu 16 with environment variables before installation.

```
export SERIES=${SERIES:-xenial} 
./startup.sh
```

## Environment variables
Environment variable list:
- SERIES - version of ubuntu, bionic by default
- CONTAINER_REGISTRY - by default "opencontrailnightly"
- CONTRAIL_CONTAINER_TAG - by default "ocata-master-latest"
