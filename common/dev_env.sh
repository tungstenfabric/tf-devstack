#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"
source "$my_dir/functions.sh"

pushd $WORKSPACE

# get tf-dev-env
echo
echo [get tf-dev-env]
echo cleanup old if exists
[ -d ./tf-dev-env ] && rm -rf ./tf-dev-env
git clone --depth 1 --single-branch https://github.com/tungstenfabric/tf-dev-env.git

# build all
echo
echo [build all containers]
build_opts="WORKSPACE=$WORKSPACE AUTOBUILD=1"
[ -n "${BUILD_TEST_CONTAINERS}" ] && build_opts+=" BUILD_TEST_CONTAINERS=${BUILD_TEST_CONTAINERS}"
$build_opts sudo -E ./tf-dev-en/run.sh

popd
