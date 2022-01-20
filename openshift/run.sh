#!/bin/bash -e

set -eo pipefail

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

[ "${DEBUG,,}" == "true" ] && set -x

source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

source "$my_dir/definitions.sh"
source "$my_dir/functions.sh"

# constants
export PROVIDER=${PROVIDER:-"kvm"} # kvm | openstack | aws

if [ -e "$my_dir/providers/${PROVIDER}/definitions" ] ; then
  source "$my_dir/providers/${PROVIDER}/definitions"
fi

export PATH="$HOME:$PATH"

# stages declaration
declare -A STAGES=( \
  ["all"]="machines manifest openshift tf wait logs" \
  ["default"]="machines manifest openshift tf wait" \
  ["platform"]="machines" \
)

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function machines() {
  echo "$DISTRO detected"
  if [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" ]]; then
    if ! sudo yum repolist | grep -q epel ; then
      sudo yum install -y epel-release
    fi
    sudo yum install -y wget python3 python3-setuptools python3-pip iproute jq bind-utils git
    if [[ "$PROVIDER" == "aws" ]]; then
      sudo yum install -y awscli
    fi
  elif [ "$DISTRO" == "ubuntu" ]; then
    export DEBIAN_FRONTEND=noninteractive
    sudo -E apt-get update
    sudo -E apt-get install -y wget python-setuptools python3-distutils python3-pip iproute2 python-crypto jq dnsutils
    if [[ "$PROVIDER" == "aws" ]]; then
      sudo -E apt-get install -y awscli
    fi
  else
    echo "Unsupported OS version"
    exit 1
  fi

  # Jinja2 is used for creating configs in the `tf-openstack` scripts
  sudo python3 -m pip install jinja2

  if [[ "$PROVIDER" != "aws" ]]; then
    ${my_dir}/providers/${PROVIDER}/destroy_cluster.sh
  fi

  set_ssh_keys

  rm -rf ${INSTALL_DIR}
  mkdir -p ${INSTALL_DIR}/openshift ${INSTALL_DIR}/manifests
  
  download_artefacts

  if [[ "${OPENSHIFT_AI_INSTALLER,,}" != 'true' ]]; then
    if [[ "$PROVIDER" == "kvm" ]]; then
      prepare_rhcos_install
    fi
    prepare_install_config
  fi
}

# copy-paste from operator deployer
function manifest() {
  # when Jenkins runs it on same slave - we have to clear previous copy
  if [[ ${KEEP_SOURCES,,} != 'true' ]]; then
    rm -rf $OPERATOR_REPO $OPENSHIFT_REPO
  fi

  # get tf-operator
  if [[ ! -d $OPERATOR_REPO ]] ; then
    if ! fetch_deployer_no_docker tf-operator-src $OPERATOR_REPO ; then
      echo "WARNING: failed to fetch tf-operator-src, use github"
      git clone https://github.com/tungstenfabric/tf-operator.git $OPERATOR_REPO
    fi
  fi

    # get tf-openshift
  if [[ ! -d $OPENSHIFT_REPO ]]; then
    if ! fetch_deployer_no_docker tf-openshift-src $OPENSHIFT_REPO ; then
      echo "WARNING: failed to fetch tf-openshift-src, use github"
      git clone https://github.com/tungstenfabric/tf-openshift.git $OPENSHIFT_REPO
    fi
  fi

  # prepare kustomize for operator
  export CONFIGDB_MIN_HEAP_SIZE=${CONFIGDB_MIN_HEAP_SIZE:-"1g"}
  export CONFIGDB_MAX_HEAP_SIZE=${CONFIGDB_MAX_HEAP_SIZE:-"4g"}
  export ANALYTICSDB_MIN_HEAP_SIZE=${ANALYTICSDB_MIN_HEAP_SIZE:-"1g"}
  export ANALYTICSDB_MAX_HEAP_SIZE=${ANALYTICSDB_MAX_HEAP_SIZE:-"4g"}
  export VROUTER_GATEWAY=${VROUTER_GATEWAY:-$(get_vrouter_gateway)}
  if [[ -n $DATA_NETWORK ]] && [[ -z $VROUTER_GATEWAY ]] ; then
    echo "ERROR: for multi-NIC setup VROTER_GATEWAY should be set"
    exit 1
  fi
  if [[ -n "$SSL_CAKEY" && -n "$SSL_CACERT" ]] ; then
    export TF_ROOT_CA_KEY_BASE64=$(echo "$SSL_CAKEY" | base64 -w 0)
    export TF_ROOT_CA_CERT_BASE64=$(echo "$SSL_CACERT" | base64 -w 0)
  fi
  $OPERATOR_REPO/contrib/render_manifests.sh

  # Copy manifests from `tf-openshift` and `tf-operator` to the install directory
  if [[ -n "${OCP_MANIFESTS_DIR}" ]]; then
    cp ${OCP_MANIFESTS_DIR}/* ${INSTALL_DIR}/manifests
  else
    $OPENSHIFT_REPO/scripts/apply_install_manifests.sh "$INSTALL_DIR"
  fi

  if [[ "${OPENSHIFT_AI_INSTALLER,,}" == 'true' || "$PROVIDER" == "aws" ]] ; then
    for file in $(ls $OPERATOR_REPO/deploy/crds); do
      cp $OPERATOR_REPO/deploy/crds/$file $INSTALL_DIR/manifests/01_$file
    done
    for file in namespace service-account role cluster-role role-binding cluster-role-binding ; do
      cp $OPERATOR_REPO/deploy/kustomize/base/operator/$file.yaml $INSTALL_DIR/manifests/02-tf-operator-$file.yaml
    done
    oc kustomize $OPERATOR_REPO/deploy/kustomize/operator/templates/ | sed -n 'H; /---/h; ${g;p;}' > $INSTALL_DIR/manifests/02-tf-operator.yaml
    oc kustomize $OPERATOR_REPO/deploy/kustomize/contrail/templates/ > $INSTALL_DIR/manifests/03-tf.yaml
  fi
}

function openshift() {
  local install_script="install_openshift.sh"
  if [[ "${OPENSHIFT_AI_INSTALLER,,}" == 'true' ]]; then
    install_script="install_openshift_ai.sh"
  fi
  # TODO: somehow move machine creation to machines
  ${my_dir}/providers/${PROVIDER}/${install_script}
  kubeconfig_copy
}

function tf() {
  if [[ "$PROVIDER" == "aws" ]]; then
    # IPI deploy
    # When deploy on AWS, we apply crds and manifests before openshift installing
    # in aws/install_openshift.sh
    echo "INFO: in AWS tf step does nothing, all is done in openshift step"
    return
  fi

  if [[ "${OPENSHIFT_AI_INSTALLER,,}" != 'true' ]]; then
    wait_cmd_success "oc get pods" 15 480

    # If we apply cn/tf manifests from directory, we not need to apply any after
    if [[ -n "${OCP_MANIFESTS_DIR}" ]]; then
      # Get bootstrap aggreagation CA and add it to kubernetes cm
      ${my_dir}/providers/${PROVIDER}/patch_aggregator_ca.sh
    else
      echo "INFO: apply CRD-s  $(date)"
      wait_cmd_success "oc apply -f ${OPERATOR_REPO}/deploy/crds/" 5 60

      echo "INFO: wait for CRD-s  $(date)"
      wait_cmd_success 'oc wait crds --for=condition=Established --timeout=2m managers.tf.tungsten.io' 1 2

      echo "INFO: apply operator and TF templates  $(date)"
      # apply operator
      wait_cmd_success "oc apply -k ${OPERATOR_REPO}/deploy/kustomize/operator/templates/" 5 60
      # apply TF cluster
      wait_cmd_success "oc apply -k ${OPERATOR_REPO}/deploy/kustomize/contrail/templates/" 5 60
    fi

    echo "INFO: wait for bootstrap complete  $(date)"
    wait_cmd_success "openshift-install --dir=${INSTALL_DIR} wait-for bootstrap-complete" 1 2 0

    echo "INFO: destroy bootstrap  $(date)"
    ${my_dir}/providers/${PROVIDER}/destroy_bootstrap.sh

    echo "INFO: start approve certs thread $(date)"
    monitor_csr &
    mpid=$!

    echo "INFO: wait for ingress controller  $(date)"
    wait_cmd_success "oc get ingresscontroller default -n openshift-ingress-operator -o name" 15 60

    # if no agents nodes - masters are schedulable, no needs patch ingress to re-schedule it on masters
    # (agent nodes is set to node_ip if not set externally)
    if [[ "$AGENT_NODES" != "$NODE_IP" ]] ; then
      local controller_count=$(echo $CONTROLLER_NODES | wc -w)
      echo "INFO: patch ingress controller count=$controller_count $(date)"
      wait_cmd_success "patch_ingress_controller ${controller_count}" 3 10
    fi

    # TODO: move it to wait stage
    echo "INFO: wait for install complete $(date)"
    wait_cmd_success "openshift-install --dir=${INSTALL_DIR} wait-for install-complete" 1 2 0

    echo "INFO: stop csr approving monitor: pid=$mpid"
    kill $mpid
    wait $mpid || true
    echo "INFO: csr approving monitor stopped"
  fi

  local ntp=${my_dir}/providers/${PROVIDER}/sync_ntp.sh
  if [ -e $ntp ]; then
    echo "INFO: sync time  $(date)"
    bash -x $ntp
  fi

  echo "INFO: oc get nodes"
  oc get nodes -o wide

  echo "INFO: oc get co"
  oc get co

  echo "INFO: problem pods"
  oc get pods -A | grep -v 'Runn\|Compl'
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
  # Services to check in wait stage
  CONTROLLER_SERVICES['config-database']=""
  CONTROLLER_SERVICES['config']+="dnsmasq "
  CONTROLLER_SERVICES['_']+="rabbitmq stunnel zookeeper "

  local controllers="`oc get nodes -o wide | awk '/ master | master,worker /{print $6}' | tr '\n' ' '`"
  echo "INFO: is_active: controller_nodes: $controllers"
  
  local agents="`oc get nodes -o wide | awk '/ worker /{print $6}' | tr '\n' ' '`"
  echo "INFO: is_active: agent_nodes: $agents"

  check_kubernetes_resources_active statefulset.apps oc
  check_kubernetes_resources_active deployment.apps oc
  check_pods_active oc
  check_tf_active core "$controllers $agents"
  check_tf_services core "$controllers" "$agents"
}

function collect_deployment_env() {
  if ! is_after_stage 'wait' ; then
    return 0
  fi

  export CONTROLLER_NODES="`oc get nodes -o wide | awk '/ master |master,worker/{print $6}' | tr '\n' ' '`"
  echo "INFO: controller_nodes: $CONTROLLER_NODES"
  export AGENT_NODES="`oc get nodes -o wide | awk '/ worker /{print $6}' | tr '\n' ' '`"
  echo "INFO: agent_nodes: $AGENT_NODES"

  DEPLOYMENT_ENV['CONTROL_NODES']="$CONTROLLER_NODES"
  DEPLOYMENT_ENV['SSH_USER']="core"
  DEPLOYMENT_ENV['DOMAINSUFFIX']="${KUBERNETES_CLUSTER_NAME}.${KUBERNETES_CLUSTER_DOMAIN}"
  # always ssl enabled
  DEPLOYMENT_ENV['SSL_ENABLE']='true'
  # use first pod cert
  local sts="$(oc get pod -n tf -o json config1-config-statefulset-0)"
  local podIP=$(echo "$sts" | jq -c -r ".status.podIP")
  local podSercret=$(oc get secret -n tf -o json config1-secret-certificates)
  DEPLOYMENT_ENV['SSL_KEY']=$(echo "$podSercret" | jq -c -r ".data.\"server-key-${podIP}.pem\"")
  DEPLOYMENT_ENV['SSL_CERT']=$(echo "$podSercret" | jq -c -r ".data.\"server-${podIP}.crt\"")
  local ca_cert="$SSL_CACERT"
  if [ -z "$ca_cert" ] ; then
    ca_cert=$(kubectl get secrets -n tf contrail-ca-certificate -o json | jq -c -r  ".data.\"ca-bundle.crt\"") || true
    if [ -z "$ca_cert" ] ; then
      ca_cert=$(kubectl get configmaps -n openshift-config-managed csr-controller-ca -o json | jq -r -c ".data.\"ca-bundle.crt\"")
    fi
  fi
  if [ -z "$ca_cert" ] ; then
    echo "ERROR: CA is empty: there is no CA in both contrail-ca-certificate secret and configmaps openshift-config-managed/csr-controller-ca"
    exit 1
  fi
  DEPLOYMENT_ENV['SSL_CACERT']="$ca_cert"
}

function collect_logs() {
  collect_logs_from_machines
}

run_stages $STAGE
