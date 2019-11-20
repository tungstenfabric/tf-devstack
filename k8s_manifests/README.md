# Kubernetes manifests deployer

Kubernetes manifests deployer provides deployment for TF with Kubernetes by means of k8s manifests.

## Hardware and software requirements

Minimal:
- instance with 2 virtual CPU, 10 GB of RAM and 120 GB of disk space to deploy with Kubernetes

- Ubuntu 18.04
- CentOS 7.x

## Quick start for k8s all-in-one node

Clone and run the run.sh script for k8s_manifests

```
sudo yum install -y git
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/k8s_manifests/run.sh
```

You'll have Kubernetes deployed with TF as its CNI networking

## Environment variables
Environment variable list:
- CONTAINER_REGISTRY - by default "tungstenfabric"
- CONTRAIL_CONTAINER_TAG - by default "master-latest"
- KUBE_MANIFEST - use particular k8s manifest template or ready manifest 
- SKIP_K8S_DEPLOYMENT - skip kubespray deployment
- SKIP_MANIFEST_CREATION - skip k8s manifest creation
- SKIP_CONTRAIL_DEPLOYMENT - skip deployment of TF, false by default
- CONTRAIL_POD_SUBNET - subnet for kubernetes pod network, 10.32.0.0/12 by default
- CONTRAIL_SERVICE_SUBNET - subnet for kubernetes service network, 10.96.0.0/12 by default
