# tf-devstack/rhosp-operator
# RHOSP deployment with Contrail Control plane deployed as a side in a K8S cluster
# that is deployed on the Overcloud nodes provisioned by RHOSP

Contrail Control plane is deployed as a TF Operator based deployment in a K8S cluster

## Requirements

Red Hat account is needed for setting RHEL subscription.


## Simple KVM based virtual non-HA setup

### Prerequisites

- KVM is prepared for [RHOSP deployment as described in KVM prerequisites](rhosp/README.md)

- Download tf-devstack
    ``` bash
    # Run on KVM

    # Download tf-devstack
    sudo yum install -y git
    git clone http://github.com/tungstenfabric/tf-devstack
    ```

### Contrail Control plane installation

1. Prepare Contrail root certificate and private key

    ``` bash
    # Run on KVM
    if [ ! -e ca.key.pem ] || [ ! -e ca.crt.pem ] ; then
        ./tf-devstack/contrib/create_ca_certs.sh
    fi
    export SSL_CAKEY=$(cat ca.key.pem)
    export SSL_CACERT=$(cat ca.crt.pem)
    # If RHOSP to be deployed with IPA it is needed to use bundled SSL_CACERT
    # (assuming ipa ca cert if downloaded to /etc/ipa/ca.crt)
    # export SSL_CACERT=$(cat ca.crt.pem /etc/ipa/ca.crt)
    ```

2. Quick start RHOSP16 non-HA setup

    - Deploy RHOSP setup with 1 Openstack controller, 1 Compute and 1 Operator based Contrail Controller

    ``` bash
    # Run on KVM
    # Adjust RH subscription parameters
    export ENABLE_RHEL_REGISTRATION=true
    export RHEL_USER="<RH account>"
    export RHEL_PASSWORD="<RH account password>"
    export RHEL_POOL_ID="<RH subscription pool id>"
    export PROVIDER=kvm
    export DEPLOYER=rhosp
    export OPENSTACK_VERSION=train
    export ENABLE_TLS='local'
    export CONTROL_PLANE_ORCHESTRATOR='operator'

    ./tf-devstack/rhosp/create_env.sh
    ./tf-devstack/rhosp/run.sh platform
    ./tf-devstack/rhosp/run.sh tf
    ```

3. Deploy K8S cluster on Operator based Contrail Controller node

    - Copy CA files to Operator based Contrail Controller node
    ``` bash
    # get IP of the Contrail Controller node node
    cc_ip=$(ssh stack@192.168.20.2 bash -c "source stackrc; openstack server list -c Networks -f value --name contrailcontroller | cut -d '=' -f 2)"
    scp ca.key.pem ca.crt.pem heat-admin@$cc_ip:
    ```

    - Setup simple non-HA K8S cluster
    ``` bash
    # SSH to Operator based Contrail Controller node
    ssh heat-admin@$cc_ip

    # Run on Overcloud node for Contrail Controller
    sudo yum install -y git
    git clone http://github.com/tungstenfabric/tf-devstack
    export CONTAINER_REGISTRY=192.168.21.2:8787
    # Disable Contrail CNI for K8S if it is not supposed to be used there
    export CNI=default
    ./tf-devstack/rhosp/providers/common/install_k8s_crio.sh
    ```

    - Setup Contrail Control plane
    ``` bash
    git clone http://github.com/tungstenfabric/tf-operator
    # Adjust keystone options according to overcloudrc file on underloud
    export AUTH_MODE=keystone
    export KEYSTONE_AUTH_HOST=overcloud.dev.clouddomain
    export KEYSTONE_AUTH_PROTO=http
    export KEYSTONE_AUTH_ADMIN_PASSWORD=qwe123QWE
    export KEYSTONE_AUTH_REGION_NAME=regionOne
    export IPFABRIC_SERVICE_HOST=overcloud.internalapi.dev.clouddomain

    # Disable Contrail CNI for K8S if it is not supposed to be used there
    export CNI=default

    # Container registry (usually points to udnercloud)
    export CONTAINER_REGISTRY=192.168.21.2:8787/tungstenfabric

    export TF_ROOT_CA_CERT_BASE64=$(cat ca.key.pem | base64 -w 0)
    export TF_ROOT_CA_KEY_BASE64=$(cat ca.crt.pem | base64 -w 0)
    # If RHOSP to be deployed with IPA it is needed to use bundled SSL_CACERT
    # (assuming ipa ca cert if downloaded to /etc/ipa/ca.crt)
    # export SSL_CACERT=$(cat ca.crt.pem /etc/ipa/ca.crt | base64 -w 0)

    # In case of data isolation provide Tenant network as below
    # export DATA_NETWORK=10.0.0.0/24 -->

    ./tf-operator/contrib/render_manifests.sh
    kubectl apply -f ./tf-operator/deploy/crds/
    kubectl wait crds --for=condition=Established --timeout=2m managers.tf.tungsten.io
    kubectl apply -k ./tf-operator/deploy/kustomize/operator/templates/
    kubectl apply -k ./tf-operator/deploy/kustomize/contrail/templates/
    ```

    - wait till setup completed and check Contrail status

4. Check RHOSP Overcloud nodes

    - ssh to each compute node and verify Contrail status

    - ensure Overcloud Contrail neutron plugin works (e.g. check list of Overcloud networks)
