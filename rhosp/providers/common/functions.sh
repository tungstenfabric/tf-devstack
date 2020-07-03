#!/bin/bash

function is_registry_insecure() {
    echo "DEBUG: is_registry_insecure: $@"
    local registry=`echo $1 | sed 's|^.*://||' | cut -d '/' -f 1`
    if  curl -s -I --connect-timeout 60 http://$registry/v2/ ; then
        echo "DEBUG: is_registry_insecure: $registry is insecure"
        return 0
    fi
    echo "DEBUG: is_registry_insecure: $registry is secure"
    return 1
}

function set_rhosp_version() {
    case "$OPENSTACK_VERSION" in
    "queens" )
        export RHEL_VERSION='rhel7'
        export RHOSP_VERSION='rhosp13'
        ;;
    "train" )
        export RHEL_VERSION='rhel8'
        export RHOSP_VERSION='rhosp16'
        ;;
    *)
        echo "Variable OPENSTACK_VERSION is unset or incorrect"
        exit 1
        ;;
esac
}