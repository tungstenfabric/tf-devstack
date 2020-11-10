# tf-devstack

tf-devstack is a tool for deployment of Tungsten Fabric from published containers or building and deploying from sources.

It is similar to the OpenStack's devstack tool and
allows bringing up Tungsten Fabric along with Kubernetes of OpenStack cloud on an all-in-one single node deployment.

Possible deployment methods are:

- [k8s manifests](https://github.com/tungstenfabric/tf-devstack/tree/master/k8s_manifests)
- [ansible](https://github.com/tungstenfabric/tf-devstack/tree/master/ansible)
- [helm](https://github.com/tungstenfabric/tf-devstack/tree/master/helm)
- [juju](https://github.com/tungstenfabric/tf-devstack/tree/master/juju)
- [rhosp](https://github.com/tungstenfabric/tf-devstack/tree/master/rhosp)

Please see particular deployment method readmes for details.


## Full TF dev suite

IMPORTANT: some of the parts and pieces are still under construction

Full TF dev suite consists of:

- [tf-dev-env](https://github.com/tungstenfabric/tf-dev-env) - develop and build TF
- [tf-devstack](https://github.com/tungstenfabric/tf-devstack) - deploy TF
- [tf-dev-test](https://github.com/tungstenfabric/tf-dev-test) - test deployed TF

Each of these tools can be used separately or in conjunction with the other two. They are supposed to be invoked in the sequence they were listed and produce environment (conf files and variables) seamlessly consumable by the next tool.

They provide two main scripts:

- run.sh
- cleanup.sh

Both these scripts accept targets (like ``run.sh build``) for various actions.

Typical scenarios are (examples are given for centos):

## Developer's scenario

Typical developer's scenario could look like this:

### 1. Preparation part

Run a machine, for example AWS instance or a VirtualBox (powerful with lots of memory - 16GB+ recommended- )

Enable passwordless sudo for your user
(for centos example: [serverfault page](https://serverfault.com/questions/160581/how-to-setup-passwordless-sudo-on-linux))

Install git:

``` bash
sudo yum install -y git
```

### 2. tf-dev-env part

Clone tf-dev-env:

``` bash
git clone http://github.com/tungstenfabric/tf-dev-env
```

Prepare the build container and fetch TF sources:

``` bash
tf-dev-env/run.sh
```

Make required changes in sources fetched to contrail directory. For example, fetch particular review for controller (you can find download link in the gerrit review):

``` bash
cd contrail/controller
git fetch "https://review.opencontrail.org/Juniper/contrail-controller" refs/changes/..... && git checkout FETCH_HEAD
cd ../../
```

Run TF build:

``` bash
tf-dev-env/run.sh build
```

### 3. tf-devstack part

Clone tf-devstack:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
```

Deploy TF by means of k8s manifests, for example:

``` bash
tf-devstack/k8s_manifests/run.sh
```

#### 3.1 Using targets

If you're on VirtualBox, for example, and want to snapshot k8s deployment prior to TF deployment you can use run.sh targets like:

``` bash
tf-devstack/k8s_manifests/run.sh platform
```

and then:

``` bash
tf-devstack/k8s_manifests/run.sh tf
```

Along with cleanup of particular target you can do tf deployment multiple times:

``` bash
tf-devstack/k8s_manifests/cleanup.sh tf
```

### 4. tf-dev-test part

Clone tf-dev-test:

``` bash
git clone http://github.com/tungstenfabric/tf-dev-test
```

Test the deployment by smoke tests, for example:

``` bash
tf-dev-test/smoke/run.sh
```

## Evaluation scenario

Typical developer's scenario could look like this:

### 1. Preparation part

Run a machine, for example AWS instance or a VirtualBox (powerful with lots of memory - 16GB+ recommended- )

Enable passwordless sudo for your user
(for centos example: [serverfault page](https://serverfault.com/questions/160581/how-to-setup-passwordless-sudo-on-linux))

Install git:

``` bash
sudo yum install -y git
```

### 2. tf-devstack part

Clone tf-devstack:

``` bash
git clone http://github.com/tungstenfabric/tf-devstack
```

Deploy TF by means of k8s manifests, for example:

``` bash
tf-devstack/k8s_manifests/run.sh
```

Or if you want to deploy with the most recent sources from master use:

``` bash
tf-devstack/k8s_manifests/run.sh master
```
