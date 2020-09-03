#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

tf_charms_image=tf-charms-src

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build juju machines k8s openstack tf wait logs" \
    ["default"]="juju machines k8s openstack tf wait" \
    ["master"]="build juju machines k8s openstack tf wait" \
    ["platform"]="juju machines k8s openstack" \
)

export PATH=$PATH:/snap/bin

# default env variables
export DEPLOYER='juju'
# max wait in seconds after deployment (openstack ~ 1300, k8s ~ 2100, maas ~ 2400???3600)
export WAIT_TIMEOUT=${WAIT_TIMEOUT:-3600}
export JUJU_REPO=${JUJU_REPO:-$WORKSPACE/tf-charms}
export ORCHESTRATOR=${ORCHESTRATOR:-kubernetes}  # openstack | kubernetes
export CLOUD=${CLOUD:-local}  # aws | local | manual
export DATA_NETWORK=${DATA_NETWORK:-}
export AUTH_PASSWORD="password"

AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-''}
AWS_SECRET_KEY=${AWS_SECRET_KEY:-''}
AWS_REGION=${AWS_REGION:-'us-east-1'}

MAAS_ENDPOINT=${MAAS_ENDPOINT:-''}
MAAS_API_KEY=${MAAS_API_KEY:-''}

export UBUNTU_SERIES=${UBUNTU_SERIES:-'bionic'}
export OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}
export VIRT_TYPE=${VIRT_TYPE:-'qemu'}

export CONTAINER_REGISTRY
export NODE_IP
export VIRTUAL_IPS

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=(\
    ['AUTH_URL']=""
    ['AUTH_PORT']="35357"
    ['AUTH_DOMAIN']="admin_domain"
    ['AUTH_PASSWORD']="$AUTH_PASSWORD"
    ['SSH_USER']="ubuntu"
)

function build() {
    "$my_dir/../common/dev_env.sh"
}

function logs() {
    local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
    set +e
    create_log_dir

set -x
    cat <<EOF >/tmp/logs.sh
#!/bin/bash
tgz_name=\$1
export WORKSPACE=/tmp/juju-logs
export TF_LOG_DIR=/tmp/juju-logs/logs
export SSL_ENABLE=$SSL_ENABLE
sudo apt-get install -y lsof
cd /tmp/juju-logs
source ./collect_logs.sh
collect_docker_logs
collect_juju_logs
collect_contrail_status
collect_system_stats
collect_contrail_logs
collect_openstack_logs
collect_kubernetes_logs
collect_kubernetes_objects_info
chmod -R a+r logs
pushd logs
tar -czf \$tgz_name *
popd
cp logs/\$tgz_name \$tgz_name
rm -rf logs
EOF
chmod a+x /tmp/logs.sh

    local machines=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | awk '{print $1}'`
    local machine=''
    for machine in $machines ; do
        local tgz_name=`echo "logs-$machine.tgz" | tr '/' '-'`
        mkdir -p $TF_LOG_DIR/$machine
        command juju ssh $machine "mkdir -p /tmp/juju-logs"
        command juju scp $my_dir/../common/collect_logs.sh $machine:/tmp/juju-logs/collect_logs.sh
        command juju scp /tmp/logs.sh $machine:/tmp/juju-logs/logs.sh
        command juju ssh $machine /tmp/juju-logs/logs.sh $tgz_name
        command juju scp $machine:/tmp/juju-logs/$tgz_name $TF_LOG_DIR/$machine/
        pushd $TF_LOG_DIR/$machine/
        tar -xzf $tgz_name
        rm -rf $tgz_name
        popd
    done
    collect_juju_status

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    rm -rf $TF_LOG_DIR

    # Restore errexit state
    if [[ $errexit_state == 1 ]]; then
        set -e
    fi
}

function juju() {
    $my_dir/../common/deploy_juju.sh
}

function machines() {
    if [[ $CLOUD == 'manual' ]] ;then
        if [[ $(( $CONTROLLERS_COUNT % 2 )) -eq 0 ]]; then
            echo "controllers' amount should be odd. now it is $CONTROLLERS_COUNT."
            exit 0
        fi
        $my_dir/../common/add_juju_machines.sh
    fi
    if [[ $ORCHESTRATOR == 'all' ]] ; then
        # in case k8s is deploying before lxd container creating,
        # lxd have wrong parent in config and can't get IP address
        # to prevent it we starts lxd before
        command juju deploy ubuntu --to lxd:0
        command juju add-unit ubuntu --to 0
    fi

    sudo apt-get update -u && sudo apt-get install -y jq dnsutils
}

function openstack() {
    if [[ "$ORCHESTRATOR" != "openstack" && $ORCHESTRATOR != 'all' ]]; then
        echo "INFO: Skipping openstack deployment"
        return
    fi

    if [[ "$UBUNTU_SERIES" == 'bionic' && "$OPENSTACK_VERSION" == 'queens' ]]; then
        export OPENSTACK_ORIGIN="distro"
    else
        export OPENSTACK_ORIGIN="cloud:$UBUNTU_SERIES-$OPENSTACK_VERSION"
    fi
    if [ $CLOUD == 'manual' ]; then
        export BUNDLE="$my_dir/files/bundle_openstack_man.yaml.tmpl"
    else
        export BUNDLE="$my_dir/files/bundle_openstack_aio.yaml.tmpl"
    fi

    if [ $CLOUD == 'maas' ] ; then
        IPS_COUNT=`echo $VIRTUAL_IPS | wc -w`
        if [[ "$IPS_COUNT" != 7 ]] && [[ "$IPS_COUNT" != 1 ]] ; then
            echo "We support deploy with 7 virtual ip addresses only now."
            echo "You must specify the first address in the range or all seven IP in VIRTUAL_IPS variable."
            exit 0
        fi
        if [[ "$IPS_COUNT" = 1 ]] ; then
            export VIRTUAL_IPS=$(prips $(netmask ${VIRTUAL_IPS} | tr -d "[:space:]") | \
                grep -P "^${VIRTUAL_IPS%/*}$"  -A6 | tr '\n' ' ')
        fi
        export BUNDLE="$my_dir/files/bundle_openstack_maas_ha.yaml.tmpl"
    fi
    $my_dir/../common/deploy_juju_bundle.sh
}

function k8s() {
    if [[ "$ORCHESTRATOR" != "kubernetes" && $ORCHESTRATOR != 'all' ]]; then
        echo "INFO: Skipping k8s deployment"
        return
    fi
    export BUNDLE="$my_dir/files/bundle_k8s.yaml.tmpl"
    $my_dir/../common/deploy_juju_bundle.sh
}

function tf() {
    if [ $CLOUD == 'maas' ] ; then
        TF_UI_IP=$(command juju show-machine 0 --format tabular | grep '^0\s' | awk '{print $3}')
        export BUNDLE="$my_dir/files/bundle_contrail_maas_ha.yaml.tmpl"
    elif [[ $CLOUD == 'manual' ]]; then
        export BUNDLE="$my_dir/files/bundle_contrail_man.yaml.tmpl"
    else
        export BUNDLE="$my_dir/files/bundle_contrail.yaml.tmpl"
    fi
    # get contrail-charms
    [ -d $JUJU_REPO ] || fetch_deployer_no_docker $tf_charms_image $JUJU_REPO \
                      || git clone https://github.com/tungstenfabric/tf-charms $JUJU_REPO
    cd $JUJU_REPO

    $my_dir/../common/deploy_juju_bundle.sh

    # add relations between orchestrator and Contrail
    if [[ $ORCHESTRATOR == 'openstack' || $ORCHESTRATOR == 'all' ]] ; then
        command juju add-relation contrail-keystone-auth keystone
        command juju add-relation contrail-openstack neutron-api
        command juju add-relation contrail-openstack heat
        command juju add-relation contrail-openstack nova-compute
        command juju add-relation contrail-agent:juju-info nova-compute:juju-info
    fi
    if [[ $ORCHESTRATOR == 'kubernetes' || $ORCHESTRATOR == 'all' ]] ; then
        command juju add-relation contrail-kubernetes-node:cni kubernetes-master:cni
        command juju add-relation contrail-kubernetes-node:cni kubernetes-worker:cni
        command juju add-relation contrail-kubernetes-master:kube-api-endpoint kubernetes-master:kube-api-endpoint
        command juju add-relation contrail-agent:juju-info kubernetes-worker:juju-info
    fi
    if [[ $ORCHESTRATOR == 'all' ]] ; then
        command juju add-relation kubernetes-master keystone
        command juju config kubernetes-master authorization-mode="Node,RBAC"
        command juju config kubernetes-master enable-keystone-authorization=true
    fi

    JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
    # fix /etc/hosts
    for machine in $JUJU_MACHINES ; do
        if [ $CLOUD == 'aws' ] ; then
            # we need to wait while machine is up for aws deployment
            wait_cmd_success 'juju ssh $machine "uname -a"'
        fi
        juju_node_ip=`$(which juju) ssh $machine "hostname -i" 2>/dev/null | tr -d '\r' | cut -f 1 -d ' '`
        juju_node_hostname=`$(which juju) ssh $machine "hostname" 2>/dev/null | tr -d '\r' | cut -f 1 -d ' '`
        command juju ssh $machine "sudo bash -c 'echo $juju_node_ip $juju_node_hostname >> /etc/hosts'" 2>/dev/null
    done

    # show results
    TF_UI_IP=${TF_UI_IP:-"$NODE_IP"}
    echo "Tungsten Fabric Web UI will be available at https://$TF_UI_IP:8143"
    echo "Use admin/password to log in (use 'admin_domain' as domain in case of OpenStack deployment)"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    local status=`$(which juju) status`
    if [[ $status =~ "error" ]]; then
        echo "ERROR: Deployment has failed because juju state is error"
        echo "$status"
        exit 1
    fi
    [[ ! $(echo "$status" | egrep 'executing|blocked|waiting') ]]
}

function collect_deployment_env() {
    if [[ $ORCHESTRATOR == 'openstack' || "$ORCHESTRATOR" == "all" ]] ; then
        DEPLOYMENT_ENV['AUTH_URL']="http://$(command juju status keystone --format tabular | grep 'keystone/' | head -1 | awk '{print $5}'):5000/v3"
    fi
    controller_nodes="`command juju status --format json | jq '.applications["contrail-controller"]["units"][]["public-address"]'`"
    if [[ -n "$controller_nodes" ]] ; then
        export CONTROLLER_NODES="$(echo $controller_nodes | sed 's/\"//g')"
    fi
    agent_nodes="`command juju status --format json | jq '.applications["nova-compute"]["units"][]["public-address"]'`"
    if [[ -n "$agent_nodes" ]] ; then
        export AGENT_NODES="$(echo $agent_nodes | sed 's/\"//g')"
    fi
    if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
        # in case of Juju several files can be placed inside subfolders (for different charms). take any.
        DEPLOYMENT_ENV['SSL_KEY']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep server-privkey.pem | head -1 | xargs sudo base64 -w 0')"
        DEPLOYMENT_ENV['SSL_CERT']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep server.pem | head -1 | xargs sudo base64 -w 0')"
        DEPLOYMENT_ENV['SSL_CACERT']="$(command juju ssh 0 'sudo find /etc/contrail 2>/dev/null | grep ca-cert.pem | head -1 | xargs sudo base64 -w 0')"
    fi
}

run_stages $STAGE
