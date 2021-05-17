#!/bin/bash

#List of yum repositories for RHOSP16 on RHEL8
export RHEL_REPOS="rhel-8-for-x86_64-baseos-rpms,rhel-8-for-x86_64-appstream-rpms,rhel-8-for-x86_64-highavailability-rpms,ansible-2-for-rhel-8-x86_64-rpms,satellite-tools-6.5-for-rhel-8-x86_64-rpms,openstack-16.1-for-rhel-8-x86_64-rpms,fast-datapath-for-rhel-8-x86_64-rpms,rhceph-4-tools-for-rhel-8-x86_64-rpms"

if [[ "$CONTROL_PLANE_ORCHESTRATOR" == 'operator' ]] ; then
  # for kubespray & k8s
  ocp=${OPENSHIFT_VERSION:-'4.6'}
  RHEL_REPOS+=",rhocp-${ocp}-for-rhel-8-x86_64-rpms,codeready-builder-for-rhel-8-x86_64-rpms"
fi
