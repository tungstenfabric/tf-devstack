```bash
git clone https://github.com/tungstenfabric/tf-devstack.git

export PROVIDER=kvm
export DEPLOYER_CONTAINER_REGISTRY="tf-nexus.progmaticlab.com:5102"
export CONTAINER_REGISTRY="tf-nexus.progmaticlab.com:5102"
export CONTRAIL_DEPLOYER_CONTAINER_TAG=${CONTRAIL_DEPLOYER_CONTAINER_TAG:-"nightly"}
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-"nightly-ubi7"}

./tf-devstack/openshift/run.sh
```
