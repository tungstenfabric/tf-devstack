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

- CentOS 7 (x86_64) - with Updates HVM
- t2.xlarge instance type
- 120 GiB disk Storage

2. Install git to clone this repository:

``` bash
sudo yum install -y git
```

3. Clone this repository and run the startup script:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
./tf-devstack/ansible/run.sh
```

5. Wait about 30-60 minutes to complete the deployment.

## Installation configuration

Tungsten Fabric is deployed with Kubernetes as orchestrator by default.
You can select OpenStack as orchestrator with environment variables before installation.

``` bash
export ORCHESTRATOR=openstack
export OPENSTACK_VERSION=queens
./run.sh
```

OpenStack version may be selected from queens (default), ocata, rocky, train.

Also you can configure many nodes deploy:

Note: You don't need a separate node for Openstack. Openstack will be installed to first controller node automatically.

For controller nodes:

``` bash
export CONTROLLER_NODES=C1,C2,C3
```

For agent nodes:

``` bash
export AGENT_NODES=C4,C5
```

where C1, C2, C3, C4, C5 IP addresses of corresponding nodes (recommended use Private IPs from AWS)

## Customized deployments and deployment steps

run.sh accepts the following targets:

Complete deployments:

- (empty) - deploy kubernetes or openstack with TF and wait for completion
- master - build existing master, deploy kubernetes or openstack with TF, and wait for completion
- all - same as master

Individual stages:

- build - tf-dev-env container is fetched, TF is built and stored in local registry
- k8s - kubernetes is deployed (unless ORCHESTRATOR=openstack)
- openstack - openstack is deployed (unless ORCHESTRATOR=kubernetes)
- tf - TF is deployed
- wait - wait until contrail-status verifies that all components are active

## Details

To deploy Tungsten Fabric from published containers
[contrail-container-deployer playbooks](https://github.com/tungstenfabric/tf-ansible-deployer) is used. For building step
[tf-dev-env environment](https://github.com/tungstenfabric/tf-dev-env) is used.

Preparation script allows root user to connect to host via ssh, install and configure docker,
build tf-dev-control container.

Environment variable list:

- ORCHESTRATOR kubernetes by default or openstack
- OPENSTACK_VERSION queens (default), ocata or rocky, variable used when ORCHESTRATOR=openstack
- NODE_IP a IP address used as CONTROLLER_NODES and CONTROL_NODES
- CONTAINER_REGISTRY - by default "opencontrailnightly"
- CONTRAIL_CONTAINER_TAG - by default "ocata-master-latest"
- CONTRAIL_DEPLOYER_CONTAINER_TAG - by default equal to CONTRAIL_CONTAINER_TAG

## Access WebUI in AWS or other environments

If you don't have access to WebUI address you can use ssh tunneling and Firefox with proxy.
For that you should:

- run Firefox and set it to use sock5 proxy : localhost 8000
- ssh -D 8000 -N centos@TF.node.ip.address

Then use the IP:Port/login/password displayed at the end of the output produced by run.sh

## Known issues

- When the system is installed, after running cleanup.sh, repeated run.sh leads to an error
- For CentOS Linux only. If the vrouter agent does not start after installation, this is probably due to an outdated version of the Linux kernel. Update your system kernel to the latest version (yum update -y) and reboot your machine
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
