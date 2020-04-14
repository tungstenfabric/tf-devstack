#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

init_output_logging


# default env variables
export DEPLOYER='rhosp'
export RHOSP_VERSION=${RHOSP_VERSION:-'rhosp13'}
if [[ "$RHOSP_VERSION" == "rhosp16" ]]; then
    export RHEL_VERSION='rhel8'
else 
    export RHEL_VERSION='rhel7'
fi
# max wait in seconds after deployment
export WAIT_TIMEOUT=3600
#PROVIDER = [ kvm | vexx | aws ]
export PROVIDER=${PROVIDER:-'vexx'}
if [[ "$PROVIDER" == "kvm" ]]; then
    export USE_PREDEPLOYED_NODES=false
else
    export USE_PREDEPLOYED_NODES=${USE_PREDEPLOYED_NODES:-true}
fi
#IPMI_PASSOWORD (also it's AdminPassword for TripleO)
export IPMI_PASSWORD=${IPMI_PASSWORD:-'password'}
user=$(whoami)

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=(\
    ['AUTH_URL']=""
)


cd $my_dir

##### Creating ~/rhosp-environment.sh #####
if [[ ! -f ~/rhosp-environment.sh ]]; then
    cp -f $my_dir/config/common.sh ~/rhosp-environment.sh
    cat $my_dir/config/${RHEL_VERSION}_env.sh | grep '^export' >> ~/rhosp-environment.sh
    cat $my_dir/config/${PROVIDER}_env.sh | grep '^export' >> ~/rhosp-environment.sh
    #Overwrite DEPLOY_POSTFIX if it's defined
    if [[ ! -z ${DEPLOY_POSTFIX+x} ]]; then
        sed -i "s/export DEPLOY_POSTFIX=.*/export DEPLOY_POSTFIX=${DEPLOY_POSTFIX}/"  ~/rhosp-environment.sh
    fi
    echo "export USE_PREDEPLOYED_NODES=$USE_PREDEPLOYED_NODES" >> ~/rhosp-environment.sh
    echo "export PROVIDER=$PROVIDER" >> ~/rhosp-environment.sh
    echo "export RHOSP_VERSION=$RHOSP_VERSION" >> ~/rhosp-environment.sh
    echo "export RHEL_VERSION=$RHEL_VERSION" >> ~/rhosp-environment.sh
    echo "export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION" >> ~/rhosp-environment.sh 

    echo "export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG" >> ~/rhosp-environment.sh
    echo "export CONTAINER_REGISTRY=$CONTAINER_REGISTRY" >> ~/rhosp-environment.sh 
    
    echo "set +x" >> ~/rhosp-environment.sh
    echo "export IPMI_PASSWORD=\"$IPMI_PASSWORD\"" >> ~/rhosp-environment.sh
fi

source ~/rhosp-environment.sh

if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; 
    if [[ -z ${RHEL_USER+x} ]]; then
        echo "Please enter you Red Hat Credentials. RHEL_USER="
        read -sr RHEL_USER_INPUT
        export RHEL_USER=$RHEL_USER_INPUT
        echo "export RHEL_USER=$RHEL_USER" >> ~/rhosp-environment.sh
    fi

    if [[ -z ${RHEL_PASSWORD+x} ]]; then
        echo "Please enter you Red Hat Credentials. RHEL_PASSWORD="
        read -sr RHEL_PASSWORD_INPUT
        export RHEL_PASSWORD=$RHEL_PASSWORD_INPUT
        echo "export RHEL_PASSWORD=$RHEL_PASSWORD" >> ~/rhosp-environment.sh
    fi

    #Put RHEL credentials into ~/rhosp-environment.sh
    egrep -c '^export RHEL_USER=.+$' ~/rhosp-environment.sh || echo export RHEL_USER=\"$RHEL_USER\" >> ~/rhosp-environment.sh
    egrep -c '^export RHEL_PASSWORD=.+$' ~/rhosp-environment.sh || echo export RHEL_PASSWORD=\"$RHEL_PASSWORD\" >> ~/rhosp-environment.sh
fi

#Continue deployment stages with environment specific script
source $my_dir/providers/${PROVIDER}/stages.sh


function collect_deployment_env() {
    # no additinal info is needed
    :
}

run_stages $STAGE
