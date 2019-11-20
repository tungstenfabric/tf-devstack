# ansible-deployer

Ansible deployer provides ansible-based deployment for TF with OpenStack or Kubernetes.

## Hardware and software requirements

Recommended:
- AWS instance with 4 virtual CPU, 16 GB of RAM and 50 GB of disk space to deploy from published containers
- AWS instance with 4 virtual CPU, 16 GB of RAM and 80 GB of disk space to build and deploy from sources

Minimal:
- VirtualBox VM with 2 CPU, 8 GB of RAM and 30 GB of disk to deploy from published containers with Kubernetes.
- VirtualBox VM with 2 CPU, 10 GB of RAM and 30 GB of disk to deploy from published containers with OpenStack.

OS:
- Centos 7
- Ubuntu 16.04

NOTE: Windows and MacOS deployments are not supported, please use VM (like VirtualBox) with Linux to run tf-devstack on such machines.

## Quick start on an AWS instance

1. Launch the new AWS instance.

Steps:
- CentOS 7 (x86_64) - with Updates HVM
- t2.xlarge instance type
- 50 GiB disk Storage

Log into a new instance and get root access:

```
sudo su -
```

2. Install git to clone this repository:

```
yum install -y git
```

3. Clone this repository and run the startup script:

```
git clone http://github.com/tungstenfabric/tf-devstack
cd tf-devstack
./run.sh
```

5. Wait about 30-60 minutes to complete the deployment.

## Installation configuration

Tungsten Fabric is deployed with Kubernetes as orchestrator by default.
You can select OpenStack as orchestrator with environment variables before installation.

```
export ORCHESTRATOR=openstack
export OPENSTACK_VERSION=queens
./run.sh
```

OpenStack version may be selected from queens (default), ocata or rocky.

## Building step

Environment variable DEV_ENV may be defined as "true" to build Tungsten Fabric from sources.
Please, set variable BEFORE preparation script or restart preparation script:

```
export DEV_ENV=true
./run.sh
```

In this case, the instance must be rebooted manually after building and deployment.

Building step takes from one to two hours.

## Details

To deploy Tungsten Fabric from published containers
[contrail-container-deployer playbooks](https://github.com/Juniper/contrail-ansible-deployer) is used. For building step
[tf-dev-env environment](https://github.com/tungstenfabric/tf-dev-env) is used.

Preparation script allows root user to connect to host via ssh, install and configure docker,
build tf-dev-control container.

Environment variable list:
- DEV_ENV true if build step is needed, false by default
- ORCHESTRATOR kubernetes by default or openstack
- OPENSTACK_VERSION queens (default), ocata or rocky, variable used when ORCHESTRATOR=openstack
- NODE_IP a IP address used as CONTROLLER_NODES and CONTROL_NODES
- CONTAINER_REGISTRY - by default "opencontrailnightly"
- CONTRAIL_CONTAINER_TAG - by default "ocata-master-latest"


## Access WebUI in AWS or other environments

If you don't have access to WebUI address you can use ssh tunneling and Firefox with proxy.
For that you should:
- run Firefox and set it to use sock5 proxy : localhost 8000
- ssh -D 8000 -N centos@<ip address of your TF node>

Then use the IP:Port/login/password displayed at the end of the output produced by run.sh

## Known issues

- Deployment scripts are tested on CentOS 7 / Ubuntu 16.04 and AWS / Virtualbox
- Occasional errors prevent deployment of Kubernetes on a VirtualBox machine, retry can help
- One or more of Tungsten Fabric containers are in "Restarting" status after installation,
try waiting 2-3 minutes or reboot the instance
- One or more pods in "Pending" state, try to "kubectl taint nodes NODENAME node-role.kubernetes.io/master-",
where NODENAME is name from "kubectl get node"
- OpenStack/rocky web UI reports "Something went wrong!",
try using CLI (you need install python-openstackclient in virtualenv)
- OpenStack/ocata can't find host to spawn VM,
set virt_type=qemu in [libvirt] section of /etc/kolla/config/nova/nova-compute.conf file inside nova_compute container,
then restart this container
