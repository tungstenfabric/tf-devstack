# Helm deployer

Helm deployer provides Helm-based deployment for TF with OpenStack or Kubernetes.

## Hardware and software requirements

Minimal:
- instance with 4 virtual CPU, 16 GB of RAM and 120 GB of disk space to deploy with Openstack
- instance with 2 virtual CPU, 10 GB of RAM and 120 GB of disk space to deploy with Kubernetes

- Ubuntu 18.04
- CentOS 7.x

## Quick start for Openstack all-in-one node

Clone and run the startup.sh script for Helm

```
sudo yum install -y git
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/helm/startup.sh
```

You'll have Kubernetes deployed with Calico and Helm Openstack deployed with TF

## Quick start for Kubernetes all-in-one node

Clone and run the startup.sh script for Helm after setting orchestrator to kubernetes.

```
sudo yum install -y git
export ORCHESTRATOR=kubernetes
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/helm/startup.sh
```

You'll have Kubernetes deployed with TF as its CNI networking.

## Environment variables
Environment variable list:
- CONTAINER_REGISTRY - by default "opencontrailnightly"
- CONTRAIL_CONTAINER_TAG - by default "master-latest"
- ORCHESTRATOR - orchestrator for deployment, "openstack" (default) and "kubernetes" are supported
- SKIP_K8S_DEPLOYMENT - skip kubespray deployment
- SKIP_OPENSTACK_DEPLOYMENT - skip Helm OpenStack deployment (when orchestrator is set to openstack)
- SKIP_CONTRAIL_DEPLOYMENT - skip deployment of TF, false by default
- CONTRAIL_POD_SUBNET - subnet for kubernetes pod network, 10.32.0.0/12 by default
- CONTRAIL_SERVICE_SUBNET - subnet for kubernetes service network, 10.96.0.0/12 by default
- OPENSTACK_VERSION - version of Openstack, queens by default
- CNI - CNI for kubernetes, calico by default for Openstack and TF for kubernetes
