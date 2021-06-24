```bash
git clone https://github.com/tungstenfabric/tf-devstack.git

export PROVIDER=kvm
export DEPLOYER_CONTAINER_REGISTRY="tf-nexus.progmaticlab.com:5102"
export CONTAINER_REGISTRY="tf-nexus.progmaticlab.com:5102"
export CONTRAIL_DEPLOYER_CONTAINER_TAG=${CONTRAIL_DEPLOYER_CONTAINER_TAG:-"nightly"}
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG:-"nightly-ubi7"}

./tf-devstack/openshift/run.sh
```
## Installation with OpenShift on Amazon
1. Set required environment variables
```bash
export PROVIDER=aws
export AWS_ACCESS_KEY_ID="<your aws access key>"
export AWS_SECRET_ACCESS_KEY="<you aws secret access key>"
export KUBERNETES_CLUSTER_DOMAIN="<your cluster domain>"
# Note! The domain must be registered in Route 53 service
export AWS_REGION="us-east-2"
export KUBERNETES_CLUSTER_NAME="test1"
export OPENSHIFT_PULL_SECRET='<your openshift pull secret>'
export CONTROLLER_NODES="A1 A2 A3"
export AGENT_NODES="A1 A2 A3 B1 B2"
```
2. Clone this repository and run the startup script
``` bash
git clone http://github.com/tungstenfabric/tf-devstack
tf-devstack/openshift/run.sh
```

3.  Wait about 40-120 minutes to complete the deployment.