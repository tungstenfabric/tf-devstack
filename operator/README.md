# Operator deployer

Operator deployer provides deployment for TF with Kubernetes by means of k8s manifests.

## Hardware and software requirements

Minimal:

- instance with 2 virtual CPU, 16 GB of RAM and 120 GB of disk space to deploy

- CentOS 7.x

## Quick start for all-in-one node

Clone and invoke the run.sh script for operator

``` bash
sudo yum install -y git
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/operator/run.sh
```

You'll have Operator deployed with TF as its CNI networking

## Customized deployments and deployment steps

run.sh accepts the following targets:

Complete deployments:

- (empty) - deploy operator with TF as its CNI networking and wait for completion
- all - build existing master and deploy operator with TF as its CNI networking and wait for completion

Individual stages:

- build - tf-dev-env container is fetched, TF is built and stored in local registry
- k8s - kubernetes is deployed by means of kubespray
- tf - TF is deployed
- wait - wait until contrail-status verifies that all components are active

## Environment variables

Environment variable list:

TODO

## Build your own operator with tf-dev-env and deploy AIO setup
## Prepare VM with CentOS 7 with 32GB RAM, 4 CPUs, 64GB diskspace
## Run tf-operator and AIO Tingsten fabric cluster
```bash
sudo yum install -y git
git clone https://github.com/tungstenfabric/tf-dev-env.git
./tf-dev-env/run.sh fetch
```
## Make changes in the operator code if any (contrail/tf-operator/)
## Build operator and src container
```bash
./tf-dev-env/run.sh package operator-containers
./tf-dev-env/run.sh package src-containers
```
# Deploy AIO setup with locally built operator
```bash
git clone https://github.com/tungstenfabric/tf-devstack.git
export CONTRAIL_DEPLOYER_CONTAINER_TAG="latest"
export DEPLOYER_CONTAINER_REGISTRY="locahost:5000"
./tf-devstack/operator/run.sh
```

## Known Issues
