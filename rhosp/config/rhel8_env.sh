#!/bin/bash

#List of yum repositories for RHOSP16 on RHEL8
RHEL_REPOS="rhel-8-for-x86_64-baseos-rpms,rhel-8-for-x86_64-appstream-rpms,rhel-8-for-x86_64-highavailability-rpms,ansible-2-for-rhel-8-x86_64-rpms,satellite-tools-6.5-for-rhel-8-x86_64-rpms,fast-datapath-for-rhel-8-x86_64-rpms,rhceph-4-tools-for-rhel-8-x86_64-rpms,advanced-virt-for-rhel-8-x86_64-rpms"

#TODO:
# until release rhosp16.2 is in openstack-beta-for-rhel-8-x86_64-rpms
# declare -A _openstack_repo_array=( ['rhosp16.1']='16.1' ['rhosp16.2']='16.2' )
declare -A _openstack_repo_array=( ['rhosp16.1']='16.1' ['rhosp16.2']='beta' )
export _openstack_repo=${_openstack_repo_array[$RHOSP_VERSION]}
RHEL_REPOS+=",openstack-${_openstack_repo}-for-rhel-8-x86_64-rpms"

if [[ -z "$EXTERNAL_CONTROLLER_NODES" && "$CONTROL_PLANE_ORCHESTRATOR" == 'operator' ]] ; then
  # the case with own operator nodes (for kubespray & k8s)
  ocp=${OPENSHIFT_VERSION:-'4.6'}
  RHEL_REPOS+=",rhocp-${ocp}-for-rhel-8-x86_64-rpms,codeready-builder-for-rhel-8-x86_64-rpms"
fi

# to export env
export RHEL_REPOS=$RHEL_REPOS
