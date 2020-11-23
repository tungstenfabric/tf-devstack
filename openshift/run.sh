#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build platform tf wait logs" \
    ["default"]="platform tf wait" \
    ["master"]="build platform tf wait" \
    ["platform"]="platform" \
)

# constants
export DEPLOYER='openshift'
export OPENSHIFT_VERSION=${OPENSHIFT_VERSION-"3.11"}
[ -n "$OPENSHIFT_VERSION" ] && openshift_image_tag="v$OPENSHIFT_VERSION"

# max wait in seconds after deployment
export WAIT_TIMEOUT=600
deployer_image=tf-openshift-ansible-src
deployer_dir=${WORKSPACE}/tf-openshift-ansible-src

# default env variables

INVENTORY_FILE=${INVENTORY_FILE:-"$deployer_dir/inventory/hosts.aio.contrail"}

settings_file=${WORKSPACE}/tf_openhift_settings

function is_registry_insecure() {
    local registry=`echo $1 | sed 's|^.*://||' | cut -d '/' -f 1`
    if  curl -s -I --connect-timeout 60 http://$registry/v2/ ; then
        return 0
    fi
    return 1
}

function make_tf_openshift_settings_file() {
    local settings_file=$1
    cat <<EOF > $settings_file
[all:vars]
ansible_become=true
contrail_analyticsdb_jvm_extra_opts="-Xms2g -Xmx4g"
contrail_configdb_jvm_extra_opts="-Xms1g -Xmx2g"

EOF

    openshift_docker_insecure_registries=""
    [ -n "$CONTRAIL_CONTAINER_TAG" ] && echo "contrail_container_tag=\"$CONTRAIL_CONTAINER_TAG\"" >> $settings_file
    [ -n "$CONTAINER_REGISTRY" ] && {
        echo "contrail_registry=\"$CONTAINER_REGISTRY\"" >> $settings_file
        is_registry_insecure "$CONTAINER_REGISTRY" && openshift_docker_insecure_registries+=",$CONTAINER_REGISTRY"
    }

    [ -n "$openshift_image_tag" ] && echo "openshift_image_tag=\"$openshift_image_tag\"" >> $settings_file
    [ -n "$RHEL_OPENSHIFT_REGISTRY" ] && {
        echo "oreg_url=\"$RHEL_OPENSHIFT_REGISTRY/openshift3/ose-\${component}:\${version}\"" >> $settings_file
        echo "etcd_image=\"${RHEL_OPENSHIFT_REGISTRY}/rhel7/etcd:3.2.22\"" >> $settings_file
        echo "system_images_registry=\"$RHEL_OPENSHIFT_REGISTRY\"" >> $settings_file
        is_registry_insecure $RHEL_OPENSHIFT_REGISTRY && openshift_docker_insecure_registries+=",$RHEL_OPENSHIFT_REGISTRY"
    }
    [ -n "$openshift_docker_insecure_registries" ] && echo "openshift_docker_insecure_registries=\"${openshift_docker_insecure_registries#,}\"" >> $settings_file
    [ -n "$RHEL_USER" ] && echo "oreg_auth_user=\"$RHEL_USER\"" >> $settings_file
    [ -n "$RHEL_PASSWORD" ] && echo "oreg_auth_password=\"$RHEL_PASSWORD\"" >> $settings_file
    echo "INFO: config $settings_file created:"
    cat $settings_file | sed 's/password=.*$/password=*****/g' | sed 's/user=.*$/user=*****/g'
}

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function build() {
    "$my_dir/../common/dev_env.sh"
}

function platform() {
    sudo yum install -y jq iproute \
        wget git tcpdump net-tools bind-utils yum-utils iptables-services \
        bridge-utils bash-completion kexec-tools sos psacct python-netaddr \
        openshift-ansible

    if ! fetch_deployer_no_docker $deployer_image $deployer_dir ; then
        git clone https://github.com/tungstenfabric/tf-openshift-ansible $deployer_dir
    fi
    cd $deployer_dir
    if [[ -n "$OPENSHIFT_VERSION" ]] ; then
        git checkout release-$OPENSHIFT_VERSION-contrail
    fi
    # make backup of resolv.conf because openshift changes it
    [ ! -f /etc/resolv.conf.org ] && { 
        sudo cp /etc/resolv.conf /etc/resolv.conf.org
    }
    [ ! -f /etc/resolv.conf.org.bkp ] && { 
        sudo cp /etc/resolv.conf /etc/resolv.conf.org.bkp
    }
    make_tf_openshift_settings_file "$settings_file"
    # deploy pre-requisites
    ansible-playbook -i $settings_file \
        -i inventory/hosts.aio.contrail playbooks/prerequisites.yml
}

function tf() {
    [ ! -f "$settings_file" ] && {
        echo "ERROR: $settings_file doesnt exist. run.sh platform is to be called first"
        return 1
    }
    local res=0
    cd $deployer_dir
    ansible-playbook -i $settings_file \
        -i inventory/hosts.aio.contrail playbooks/deploy_cluster.yml || res=1
    # show results
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
    echo "Use admin/contrail123 to log in"
    return $res
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    check_pods_active && check_tf_active
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}

function collect_logs() {
    cp $WORKSPACE/contrail.yaml ${TF_LOG_DIR}/
    collect_logs_from_machines
}

run_stages $STAGE
