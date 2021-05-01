#!/bin/bash -e

declare -A ocp_versions=( ["4.5"]="4.5.36" ["4.6"]="4.6.21" )
OCP_VERSION=${OCP_VERSION:-"${ocp_versions[$OPENSHIFT_VERSION]}"}

OCP_MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"

INSTALL_DIR=${INSTALL_DIR:-"${WORKSPACE}/install-${KUBERNETES_CLUSTER_NAME}"}
DOWNLOADS_DIR=${DOWNLOADS_DIR:-"${WORKSPACE}/downloads-${KUBERNETES_CLUSTER_NAME}"}

CLIENT="openshift-client-linux-${OCP_VERSION}.tar.gz"
CLIENT_URL="${OCP_MIRROR}/${OCP_VERSION}/${CLIENT}"

INSTALLER="openshift-install-linux-${OCP_VERSION}.tar.gz"
INSTALLER_URL="${OCP_MIRROR}/${OCP_VERSION}/${INSTALLER}"