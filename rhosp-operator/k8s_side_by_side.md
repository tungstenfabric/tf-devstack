# tf-devstack/rhosp-operator 
# RHOSP deployment with Contrail Control plane deployed as a side in a K8S cluster

Contrail Control plane is deployed separatly as a TF Operator based deployment in a K8S cluster

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

- Ensure CentOS base image for K8S is prepared (to be run first time for kvm)
    ``` bash
    # Run on KVM

    # ensure base image is prepared (to be run first time for kvm)
    OC=centos ./tf-devstack/contrib/infra/kvm/prepare-image.sh
    ```

### Contrail Control plane installation

1. Prepare K8S VM instance

    ``` bash
    # Run on KVM
    
    # create instance
    export KVM_NETWORK="k8s"
    export DOMAIN="dev.localdomain"
    ./tf-devstack/contrib/infra/kvm/create_workers.sh
    ```

2. Prepare Contrail root certificate and private key

    ``` bash
    # Run on KVM
    if [ ! -e ca.key.pem ] || [ ! -e ca.crt.pem ] ; then
        ./tf-devstack/rhosp/providers/common/create_ca_certs.sh
    fi
    export SSL_CAKEY=$(cat ca.key.pem)
    export SSL_CACERT=$(cat ca.crt.pem)
    source stackrc.manual.env
    scp ca.key.pem ca.crt.pem centos@$instance_ip:
    ```

3.  Prepare RHOSP instances

    ``` bash
    # Run on KVM
    # Adjust RH subscription parameters
    export ENABLE_RHEL_REGISTRATION=true
    export RHEL_USER="<RH account>"
    export RHEL_PASSWORD="<RH account password>"
    export RHEL_POOL_ID="<RH subscription pool id>"
    # Adjust IP where Contrail Control plane is available
    export EXTERNAL_CONTROLLER_NODES="$instance_ip"
    export PROVIDER=kvm
    export OPENSTACK_VERSION=train
    export ENABLE_TLS='local'
    export CONTROL_PLANE_ORCHESTRATOR='operator'

    ./tf-devstack/rhosp/create_env.sh
    ```

4. Configure connectivity between RHOSP and K8S networks

    - Enable forwarding between RHOSP and K8S networks (K8S and Overcloud nodes are in different KVM networks so it is needed to add iptabels rules).
``` bash
# Assuming that K8S network name is 'k8s_1' with CIDR 10.100.0.0/24
sudo iptables -I LIBVIRT_FWI 1 -i prov-20 -d 10.100.0.0/24 -o k8s_1 -j ACCEPT 
sudo iptables -I LIBVIRT_FWI 1 -i mgmt-20 -d 10.100.0.0/24 -o k8s_1 -j ACCEPT 
sudo iptables -I LIBVIRT_FWI 1 -i k8s_1 -d 192.168.20.0/24 -o mgmt-20  -j ACCEPT
sudo iptables -I LIBVIRT_FWI 1 -i k8s_1 -d 192.168.21.0/24 -o prov-20  -j ACCEPT
```

    - Ensure K8S nodes resolves DNS names of overcloud VIPs, e.g.
``` bash
# SSH to K8S instance
ssh centos@$instance_ip

# Add FQDNs <=> VIP resolving to /etc/hosts 
cat << EOF | sudo tee -a /etc/hosts
192.168.21.200  overcloud.ctlplane.dev.localdomain
192.168.21.200  overcloud.storage.dev.localdomain
192.168.21.200  overcloud.storagemgmt.dev.localdomain
192.168.21.200  overcloud.internalapi.dev.localdomain
192.168.21.200  overcloud.dev.localdomain
EOF

# Check ping to RHOSP undercloud node
ping -c 3 192.168.20.2

# Exit to KVM
exit
```

5. Start K8S all-in-one setup with Contrail Control plane deployment

    ``` bash
    # SSH to the K8S instance
    ssh centos@$instance_ip

    # Run inside K8S VM
    export SSL_CAKEY=$(cat ca.key.pem)
    export SSL_CACERT=$(cat ca.crt.pem)
    # If RHOSP to be deployed with IPA it is needed to use bundled SSL_CACERT 
    # (assuming ipa ca cert if downloaded to /etc/ipa/ca.crt)
    # export SSL_CACERT=$(cat ca.crt.pem /etc/ipa/ca.crt)
    export AUTH_MODE='keystone'
    export IPFABRIC_SERVICE_HOST='192.168.21.200'
    export KEYSTONE_AUTH_HOST='192.168.21.200'
    export KEYSTONE_AUTH_PROTO='http'
    export KEYSTONE_AUTH_ADMIN_PASSWORD='qwe123QWE'
    export KEYSTONE_AUTH_REGION_NAME='regionOne'

    # to disable Contrail CNI for K8S cluster comment the line
    #export CNI=calico

    ./tf-devstack/operator/run.sh platform
    ./tf-devstack/operator/run.sh tf

    # Exit from ssh to K8S instance
    exit
    ```

6. Deploy RHOSP16 non-HA setup with 1 Openstack controller and 1 Compute

    ``` bash
    # Run on KVM
    ./tf-devstack/rhosp/run.sh
    ```

7. Check RHOSP Overcloud nodes

    - ssh to each compute node and verify Contrail status

    - ensure Overcloud Contrail neutron plugin works (e.g. check list of Overcloud networks)
