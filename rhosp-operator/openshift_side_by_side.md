# tf-devstack/rhosp-operator
# RHOSP deployment with Contrail Control plane deployed as a side in a OpenShift cluster

Contrail Control plane is deployed separatly as a TF Operator based deployment in an OpenShift cluster

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
    ```

2. Quick start for OpenShift minimal deployment (3 masters) with Contrail CNI

    - Invoke the run.sh script for OpenShift

        ``` bash
        # Run on KVM
        # Adjust pull secret to access: quay.io, cloud.openshift.com, registry.redhat.io, registry.connect.redhat.com
        export OPENSHIFT_PULL_SECRET='<provide here your OpenShift image pull secret>'
        export PROVIDER=kvm
        export CONTROLLER_NODES="C1,C2,C3"
        export AGENT_NODES=""

        ./tf-devstack/openshift/run.sh
        ```
    - Wait till setup completed

3. Quick start RHOSP16 non-HA setup

    - Deploy RHOSP setup with 1 Openstack controller and 1 Compute

    ``` bash
    # Run on KVM
    # Adjust RH subscription parameters
    export ENABLE_RHEL_REGISTRATION=true
    export RHEL_USER="<RH account>"
    export RHEL_PASSWORD="<RH account password>"
    export RHEL_POOL_ID="<RH subscription pool id>"
    # Adjust IP where Contrail Control plane is available
    export EXTERNAL_CONTROLLER_NODES="<IP>"
    export PROVIDER=kvm
    export OPENSTACK_VERSION=train
    export ENABLE_TLS='local'
    export CONTROL_PLANE_ORCHESTRATOR='operator'

    ./tf-devstack/rhosp/create_env.sh
    ./tf-devstack/rhosp/run.sh platform
    ./tf-devstack/rhosp/run.sh tf
    ```

5. Check connectivity between RHOSP overcloud nodes and K8S based Contrail control plane

    - ensure OpenShift nodes resolves DNS names of overcloud VIPs, e.g.
``` bash
# On KVM there is dnsmasq run that uses /etc/hosts.
# Update /etc/hosts on KVM and reload dnsmasq service
cat << EOF | sudo tee -a /etc/hosts
192.168.21.200  overcloud.ctlplane.dev.clouddomain
192.168.21.200  overcloud.storage.dev.clouddomain
192.168.21.200  overcloud.storagemgmt.dev.clouddomain
192.168.21.200  overcloud.internalapi.dev.clouddomain
192.168.21.200  overcloud.dev.clouddomain
EOF
sudo systemctl restart dnsmasq
```
    - ensure Overcloud nodes can reach K8S nodes and vice versa.
OpenShift and Overcloud nodes are in different KVM networks, it is needed to add iptabels rules, e.g.
``` bash
# Assuming that OpenShift network name is 'ocp' with CIDR 192.168.123.0/24
sudo iptables -I LIBVIRT_FWI 1 -i prov-20 -d 192.168.123.0/24 -o ocp -j ACCEPT
sudo iptables -I LIBVIRT_FWI 1 -i mgmt-20 -d 192.168.123.0/24 -o ocp -j ACCEPT
sudo iptables -I LIBVIRT_FWI 1 -i ocp -d 192.168.20.0/24 -o mgmt-20  -j ACCEPT
sudo iptables -I LIBVIRT_FWI 1 -i ocp -d 192.168.21.0/24 -o prov-20  -j ACCEPT
```

    - ssh to OpenShift node and check ping to RHOSP Overcloud Internal API VIP and FQDNs

    - ssh to Overcloud nodes and check ping to OpenShift nodes (Contrail Control plane)

6. Connect OpenShift based Contrail Control plane to the RHOSP keystone

    - Get Overcloud Keystone auth parameters from overcloudrc from undercloud node
    ``` bash
    ssh stack@192.168.20.2 cat overcloudrc
    ```

    - Update manifests with keystone info
    ``` bash
    # Assumed KVM is prepared on Ubuntu
    export KUBECONFIG="/home/ubuntu/install-test1/auth/kubeconfig"
    export PATH=$PATH:$HOME
    # Adjust options according to overcloudrc
    export AUTH_MODE='keystone'
    export IPFABRIC_SERVICE_HOST='192.168.21.200'
    export KEYSTONE_AUTH_HOST='192.168.21.200'
    export KEYSTONE_AUTH_PROTO='http'
    export KEYSTONE_AUTH_ADMIN_PASSWORD='qwe123QWE'
    export KEYSTONE_AUTH_REGION_NAME='regionOne'
    ./tf-operator/contrib/render_manifests.sh
    oc apply -k ./tf-operator/deploy/kustomize/contrail/templates/
    # Check if stateful sets are restarted
    oc -n tf get pods
    # If stateful sets are not updated apply WA:
    oc -n tf rollout restart sts \
        webui1-webui-statefulset \
        kubemanager1-kubemanager-statefulset \
        config1-config-statefulset \
        analytics1-analytics-statefulset \
        queryengine1-queryengine-statefulset \
        analyticssnmp1-analyticssnmp-statefulset \
        analyticsalarm1-analyticsalarm-statefulset
    # Wait till pods restarted
    oc -n tf get pods
    # Check Contrail status
    sudo contrail-status
    ```

7. Check RHOSP Overcloud nodes

    - ssh to each compute node and verify Contrail status

    - ensure Overcloud Contrail neutron plugin works (e.g. check list of Overcloud networks)
