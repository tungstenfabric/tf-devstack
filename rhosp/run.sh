#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export WORKSPACE=${WORKSPACE:-$(pwd)}
source "$my_dir/../common/functions.sh"
source "$WORKSPACE/rhosp-environment.sh"

#Checking if mandatory variables are defined
ensureVariable ENVIRONMENT_OS
ensureVariable PROVIDER
ensureVariable USE_PREDEPLOYED_NODES
ensureVariable ENABLE_RHEL_REGISTRATION
ensureVariable OPENSTACK_CONTAINER_REGISTRY
ensureVariable OPENSTACK_CONTAINER_TAG
ensureVariable CONTAINER_REGISTRY
ensureVariable CONTRAIL_CONTAINER_TAG
ensureVariable RHOSP_VERSION
ensureVariable RHOSP_MAJOR_VERSION
ensureVariable RHEL_VERSION
ensureVariable RHEL_MAJOR_VERSION
ensureVariable OPENSTACK_VERSION
ensureVariable SSH_USER

source "$my_dir/../common/common.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"
source "$my_dir/providers/common/common.sh"
source "$my_dir/providers/common/functions.sh"
source "$my_dir/providers/${PROVIDER}/stages.sh"

init_output_logging


# stages declaration
declare -A STAGES=( \
    ["all"]="build machines tf wait logs" \
    ["default"]="machines tf wait" \
    ["master"]="build machines tf wait" \
    ["platform"]="machines" \
)

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=(\
    ['AUTH_URL']=""
)

run_stages $STAGE
