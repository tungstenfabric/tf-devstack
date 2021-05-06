# Install ovenshift on openstack infra

Node for run installation scripts below:

- CentOS 7
- 2G RAM
- 10G Disk Space

Deploy will automatically create bootstrap node, 3 master nodes and 3 worker nodes in openstack cloud.

1. Setup you clouds.yaml file as instucted here: <https://docs.openstack.org/python-openstackclient/pike/configuration/index.html>

1. Crete two IP addresses inside your OpenStack cloud

```bash
openstack floating ip create --description "API <cluster_name>.<base_domain>" <external network>
openstack floating ip create --description "Ingress <cluster_name>.<base_domain>" <external network>
```

1. Add DNS Records to your base domain

```
api.<cluster_name>.<base_domain>.  IN  A  <API_FIP>
*.apps.<cluster_name>.<base_domain>. IN  A <apps_FIP>
```

1. Set up required env variables:

- OPENSHIFT_PUB_KEY - Public keys to be uploaded on openshift machines for user 'core'
- OPENSHIFT_PULL_SECRET - Pull secret for download openshift images <https://cloud.redhat.com/openshift/install/pull-secret>.
- KUBERNETES_CLUSTER_NAME - Cluster name for your openshift cluster. The name will be used as a part of API and Ingress domain names
- KUBERNETES_CLUSTER_NAME - base domain name for your cluster
- OPENSHIFT_API_FIP - Floating IP address for your openshift API
- OPENSHIFT_INGRESS_FIP - Floating IP address for your openshift Ingress

1. Run install script:

```bash
./install_openshift.sh
```
