#!/bin/bash -e

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"

source "$my_dir/../../../common/functions.sh"
source "$my_dir/../../definitions.sh"
source "$my_dir/../../functions.sh"

[[ -z "$AWS_ACCESS_KEY_ID" ]] && echo "AWS_ACCESS_KEY_ID is not set." && exit 1
[[ -z "$AWS_SECRET_ACCESS_KEY" ]] && echo "AWS_SECRET_ACCESS_KEY is not set." && exit 1
[[ -z "$OPENSHIFT_PULL_SECRET" ]] && echo "OPENSHIFT_PULL_SECRET is not set." && exit 1

export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export OPENSHIFT_PULL_SECRET=$OPENSHIFT_PULL_SECRET
export AWS_REGION=${AWS_REGION:-"us-east-2"}

GOLANG_URL="https://dl.google.com/go/go1.14.2.linux-amd64.tar.gz"
GOLANG="go1.14.2.linux-amd64.tar.gz"

# Download `kubectl`, `oc` and `openshift-install` to the current directory
download_artefacts

# Create openshift install config and manifests
[[ ! -d ${INSTALL_DIR} ]] && mkdir -p ${INSTALL_DIR}
[[ ! -d ${HOME}/.aws ]] && mkdir -p ${HOME}/.aws

jinja="$my_dir/../../../common/jinja2_render.py"
$jinja < $my_dir/aws_credentials.j2 > $HOME/.aws/credentials
$jinja < $my_dir/install_config.yaml.j2 > $INSTALL_DIR/install-config.yaml
./openshift-install create manifests --dir=$INSTALL_DIR

# Copy manifests from `tf-openshift` and `tf-operator` to the install directory
$OPENSHIFT_REPO/scripts/apply_install_manifests.sh "$INSTALL_DIR"
$OPERATOR_REPO/contrib/render_manifests.sh
for file in $(ls $OPERATOR_REPO/deploy/crds); do
  cp $OPERATOR_REPO/deploy/crds/$file $INSTALL_DIR/manifests/01_$file
done

for file in namespace service-account role cluster-role role-binding cluster-role-binding ; do
   cp $OPERATOR_REPO/deploy/kustomize/base/operator/$file.yaml $INSTALL_DIR/manifests/02-tf-operator-$file.yaml
done

./oc kustomize $OPERATOR_REPO/deploy/kustomize/operator/templates/ | sed -n 'H; /---/h; ${g;p;}' > $INSTALL_DIR/manifests/02-tf-operator.yaml
./oc kustomize $OPERATOR_REPO/deploy/kustomize/contrail/templates/ > $INSTALL_DIR/manifests/03-tf.yaml

# Create cluster
$my_dir/parallel.sh &
./openshift-install create cluster --dir=$INSTALL_DIR
