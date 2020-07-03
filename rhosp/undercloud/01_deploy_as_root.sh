#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ -z ${SUDO_USER+x} ]]; then
   echo "Stop. Please run this scripts with sudo"
   exit 1
fi

source /home/$SUDO_USER/rhosp-environment.sh

#Specific part of deployment
source $my_dir/${RHEL_VERSION}_deploy_as_root.sh
