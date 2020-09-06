# Kubernetes manifests deployer

Kubernetes manifests deployer provides deployment for TF with Kubernetes by means of k8s manifests.

## Hardware and software requirements

Minimal:

- instance with 2 virtual CPU, 10 GB of RAM and 120 GB of disk space to deploy with Kubernetes

- Ubuntu 18.04
- CentOS 7.x

## Quick start for k8s all-in-one node

Clone and invoke the run.sh script for k8s_manifests

``` bash
sudo yum install -y git
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/k8s_manifests/run.sh
```

You'll have Kubernetes deployed with TF as its CNI networking

## Customized deployments and deployment steps

run.sh accepts the following targets:

Complete deployments:

- (empty) - deploy kubernetes with TF as its CNI networking and wait for completion
- master - build existing master and deploy kubernetes with TF as its CNI networking and wait for completion
- all - same as master

Individual stages:

- build - tf-dev-env container is fetched, TF is built and stored in local registry
- k8s - kubernetes is deployed by means of kubespray
- manifest - manifest contrail.yaml is created from template
- tf - TF is deployed
- wait - wait until contrail-status verifies that all components are active

## Environment variables

Environment variable list:

- CONTAINER_REGISTRY - by default "tungstenfabric"
- CONTRAIL_CONTAINER_TAG - by default "master-latest"
- CONTRAIL_DEPLOYER_CONTAINER_TAG - by default equal to CONTRAIL_CONTAINER_TAG
- KUBE_MANIFEST - use particular k8s manifest template or ready manifest
- CONTRAIL_POD_SUBNET - subnet for kubernetes pod network, 10.32.0.0/12 by default
- CONTRAIL_SERVICE_SUBNET - subnet for kubernetes service network, 10.96.0.0/12 by default

## Known Issues

- For CentOS Linux only. If the vrouter agent does not start after installation, this is probably due to an outdated version of the Linux kernel. Update your system kernel to the latest version (yum update -y) and reboot your machine

## Known behavior

- After the deployment hostname will be changed to node1. This is known behaviour of kubespray