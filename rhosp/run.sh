#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"
source "$my_dir/providers/common/common.sh"
source "$my_dir/providers/common/functions.sh"
source "$my_dir/providers/${PROVIDER}/stages.sh"

init_output_logging

# stages declaration
declare -A STAGES=( \
    ["all"]="build machines undercloud overcloud tf wait logs" \
    ["default"]="machines undercloud overcloud tf wait" \
    ["master"]="build machines undercloud overcloud tf wait" \
    ["platform"]="machines undercloud overcloud" \
)

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV=(\
    ['AUTH_URL']=""
)

run_stages $STAGE
