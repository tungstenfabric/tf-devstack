# Helm deployer

Helm deployer provides Helm-based deployment for TF with OpenStack or Kubernetes.

## Hardware and software requirements

Minimal:

- instance with 4 virtual CPU, 16 GB of RAM and 120 GB of disk space to deploy with Openstack
- instance with 2 virtual CPU, 10 GB of RAM and 120 GB of disk space to deploy with Kubernetes

- Ubuntu 18.04
- CentOS 7.x

## Quick start for Openstack all-in-one node

Clone and run the run.sh script for Helm

``` bash
sudo yum install -y git
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/helm/run.sh
```

You'll have Kubernetes deployed with Calico and Helm Openstack deployed with TF

## Quick start for Kubernetes all-in-one node

Clone and run the run.sh script for Helm after setting orchestrator to kubernetes.

``` bash
sudo yum install -y git
export ORCHESTRATOR=kubernetes
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/helm/run.sh
```

You'll have Kubernetes deployed with TF as its CNI networking.

## Customized deployments and deployment steps

run.sh accepts the following targets:

Complete deployments:

- (empty) - deploy kubernetes or openstack with TF and wait for completion
- master - build existing master, deploy kubernetes or openstack with TF, and wait for completion
- all - same as master

Individual stages:

- build - tf-dev-env container is fetched, TF is built and stored in local registry
- k8s - kubernetes is deployed by means of kubespray (unless ORCHESTRATOR=openstack)
- openstack - helm openstack is deployed (unless ORCHESTRATOR=kubernetes)
- tf - TF is deployed
- wait - wait until contrail-status verifies that all components are active

## Environment variables

Environment variable list:

- CONTAINER_REGISTRY - by default "tungstenfabric"
- CONTRAIL_CONTAINER_TAG - by default "master-latest"
- ORCHESTRATOR - orchestrator for deployment, "openstack" (default) and "kubernetes" are supported
- CONTRAIL_POD_SUBNET - subnet for kubernetes pod network, 10.32.0.0/12 by default
- CONTRAIL_SERVICE_SUBNET - subnet for kubernetes service network, 10.96.0.0/12 by default
- OPENSTACK_VERSION - version of Openstack, queens by default
- CNI - CNI for kubernetes, calico by default for Openstack and TF for kubernetes

## Known Issues

- For CentOS Linux only. If the vrouter agent does not start after installation, this is probably due to an outdated version of the Linux kernel. Update your system kernel to the latest version (yum update -y) and reboot your machine
