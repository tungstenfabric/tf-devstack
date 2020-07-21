# Openshift deployer

Openshift deployer provides deployment for TF with Kubernetes by means of openshift-ansible.

## Hardware and software requirements

Minimal:

- instance with 4 virtual CPU, 16 GB of RAM and 120 GB of disk space to deploy with Kubernetes

- RHEL 7.7 (only openshift_deployment_type=openshift-entrprise is supported)

## Quick start for all-in-one node

Clone and invoke the run.sh script

``` bash
sudo yum install -y git
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/openshift/run.sh
```

You'll have minimal all-in-one Openshift deployed with TF as its CNI networking

## Customized deployments and deployment steps

run.sh accepts the following targets:

## Environment variables

Environment variable list:

- RHEL_USER - RedHat user with available subscription
- RHEL_PASSWORD - RedHat user password available subscription
- CONTAINER_REGISTRY - by default "tungstenfabric"
- CONTRAIL_CONTAINER_TAG - by default "master-latest"
- CONTRAIL_DEPLOYER_CONTAINER_TAG - by default equal to CONTRAIL_CONTAINER_TAG
- CONTRAIL_POD_SUBNET - subnet for kubernetes pod network, 10.32.0.0/12 by default
- CONTRAIL_SERVICE_SUBNET - subnet for kubernetes service network, 10.96.0.0/12 by default

## Known Issues
