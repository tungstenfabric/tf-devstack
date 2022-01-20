#!/bin/bash -e

export WORKSPACE=${WORKSPACE:-$HOME}

# supported version 4.5, 4.6, 4.8, master
# master is a laltest supported numerical version
export OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-'master'}
if [[ "$OPENSHIFT_VERSION" == 'master' ]]; then
  export OPENSHIFT_VERSION='4.6'
fi

export DEPLOYER='openshift'
export SSL_ENABLE="true"

export KUBERNETES_CLUSTER_NAME=${KUBERNETES_CLUSTER_NAME:-"test1"}
export KUBERNETES_CLUSTER_DOMAIN=${KUBERNETES_CLUSTER_DOMAIN:-"example.com"}

export KEEP_SOURCES=${KEEP_SOURCES:-false}
export OPERATOR_REPO=${OPERATOR_REPO:-$WORKSPACE/tf-operator}
export OPENSHIFT_REPO=${OPENSHIFT_REPO:-$WORKSPACE/tf-openshift}
export KUBECONFIG=${KUBECONFIG:-"${INSTALL_DIR}/auth/kubeconfig"}

# user for coreos is always 'core'
export OPENSHIFT_SSH_KEY="${HOME}/.ssh/id_rsa"
export OPENSHIFT_PUB_KEY="$(ssh-keygen -y -f $OPENSHIFT_SSH_KEY)"
export SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no"

declare -A ocp_versions=( ["4.5"]="4.5.36" ["4.6"]="4.6.23" ["4.8"]="4.8.12")
OCP_VERSION=${OCP_VERSION:-"${ocp_versions[$OPENSHIFT_VERSION]}"}

OCP_BASE_URL="https://mirror.openshift.com/pub/openshift-v4"

RHCOS_MIRROR="$OCP_BASE_URL/dependencies/rhcos"
OCP_MIRROR="$OCP_BASE_URL/clients/ocp"

INSTALL_DIR=${INSTALL_DIR:-"${WORKSPACE}/install-${KUBERNETES_CLUSTER_NAME}"}
DOWNLOADS_DIR=${DOWNLOADS_DIR:-"${WORKSPACE}/downloads-${KUBERNETES_CLUSTER_NAME}"}

CLIENT="openshift-client-linux-${OCP_VERSION}.tar.gz"
CLIENT_URL="${OCP_MIRROR}/${OCP_VERSION}/${CLIENT}"

INSTALLER="openshift-install-linux-${OCP_VERSION}.tar.gz"
INSTALLER_URL="${OCP_MIRROR}/${OCP_VERSION}/${INSTALLER}"

declare -A rhcos_versions=( ["4.5"]="4.5.6" ["4.6"]="4.6.8" ["4.8"]="4.8.2")
RHCOS_VERSION=${RHCOS_VERSION:="${rhcos_versions[$OPENSHIFT_VERSION]}"}

declare -A rhcos_images=( ["4.5"]="rhcos-metal.x86_64.raw.gz" ["4.6"]="rhcos-live-rootfs.x86_64.img" ["4.8"]="rhcos-live-rootfs.x86_64.img")
RHCOS_IMAGE="${rhcos_images[$OPENSHIFT_VERSION]}"

declare -A rhcos_kernels=( ["4.5"]="rhcos-installer-kernel-x86_64" ["4.6"]="rhcos-live-kernel-x86_64" ["4.8"]="rhcos-live-kernel-x86_64")
RHCOS_KERNEL="${rhcos_kernels[$OPENSHIFT_VERSION]}"

declare -A rhcos_initramfs_s=( ["4.5"]="rhcos-installer-initramfs.x86_64.img" ["4.6"]="rhcos-live-initramfs.x86_64.img" ["4.8"]="rhcos-live-initramfs.x86_64.img")
RHCOS_INITRAMFS="${rhcos_initramfs_s[$OPENSHIFT_VERSION]}"

declare -A versioned_rootfs_urls=( ["4.5"]="coreos.inst.image_url" ["4.6"]="coreos.live.rootfs_url" ["4.8"]="coreos.live.rootfs_url")
RHCOS_ROOTFS=${versioned_rootfs_urls[$OPENSHIFT_VERSION]}

REDHAT_SSO_URL="https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
OPENSHIFT_AI_DISABLE_SSO=${OPENSHIFT_AI_DISABLE_SSO:-'true'}
OPENSHIFT_AI_SSO_TOKEN=${OPENSHIFT_AI_SSO_TOKEN:-}

OPENSHIFT_AI_API_BASE=${OPENSHIFT_AI_API_BASE:-"https://api.openshift.com/api/assisted-install"}
OPENSHIFT_AI_API_V1="${OPENSHIFT_AI_API_BASE}/v1"
OPENSHIFT_AI_API_V2="${OPENSHIFT_AI_API_BASE}/v2"

EXTRA_NTP=${EXTRA_NTP:-"3.europe.pool.ntp.org"}

ADMIN_PASSWORD=${ADMIN_PASSWORD:-'qwe123QWE'}
