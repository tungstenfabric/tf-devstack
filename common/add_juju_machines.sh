#!/bin/bash

# Adds CONTROLLER_NODES and AGENT_NODES to model for manual deployment

set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"

for node in $CONTROLLER_NODES ; do
    if [[ $node != $NODE_IP && $CLOUD == 'manual' ]]; then
        echo "INFO: add machine $SSH_USER@$node for controller"
        juju add-machine ssh:$SSH_USER@$node
    fi
done

for node in $AGENT_NODES ; do
    if [[ $node != $NODE_IP && $CLOUD == 'manual' && ! " $CONTROLLER_NODES " =~ " $node " ]]; then
        echo "INFO: add machine $SSH_USER@$node for agent"
        juju add-machine ssh:$SSH_USER@$node
    fi
done

if [[ -n "$APT_MIRROR" ]]; then
    lxd_url=$(echo $APT_MIRROR | sed 's|mirror/archive.ubuntu.com/ubuntu/|lxd|')
fi

echo "INFO: init LXD"
for machine in $(timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $3}') ; do
    echo "INFO: init LXD on machine $machine"

    if ! juju ssh $machine lxc storage list | grep default ; then
        echo "INFO: try to init LXD on machine $machine"
        ssh $SSH_USER@$machine sudo apt-get install -y zfsutils-linux
        ssh $SSH_USER@$machine "lxd init --auto ; lxc network set lxdbr0 ipv6.address none"
        # zfs for lxd in a same disk doesn't help
        # TODO: check timings with zfs on separate disk
#        ssh $SSH_USER@$machine "lxd init --auto --storage-backend=zfs --storage-create-loop=40 ; lxc network set lxdbr0 ipv6.address none"
    fi

    # Switching to local stable LXD images
    if [[ -n "$lxd_url" ]]; then
        echo "INFO: download cached lxd image on machine $machine"
        ssh $SSH_USER@$machine "wget -nv $lxd_url/$UBUNTU_SERIES-server-cloudimg-amd64-lxd.tar.xz $lxd_url/$UBUNTU_SERIES-server-cloudimg-amd64-root.tar.xz"
        ssh $SSH_USER@$machine "lxc image import $UBUNTU_SERIES-server-cloudimg-amd64-lxd.tar.xz $UBUNTU_SERIES-server-cloudimg-amd64-root.tar.xz --alias juju/$UBUNTU_SERIES/amd64 > /dev/null"
        if [[ "$UBUNTU_SERIES" != 'bionic' ]]; then
            # some components are always binoic so we have to apply it too
            ssh $SSH_USER@$machine "wget -nv $lxd_url/bionic-server-cloudimg-amd64-lxd.tar.xz $lxd_url/bionic-server-cloudimg-amd64-root.tar.xz"
            ssh $SSH_USER@$machine "lxc image import bionic-server-cloudimg-amd64-lxd.tar.xz bionic-server-cloudimg-amd64-root.tar.xz --alias juju/bionic/amd64 > /dev/null"
        fi
        ssh $SSH_USER@$machine 'lxc image list'
        ssh $SSH_USER@$machine 'printf "\n127.0.0.1 cloud-images.ubuntu.com\n127.0.0.1 streams.ubuntu.com\n" | sudo tee -a /etc/hosts'
    fi
done

echo "INFO: juju machines added"
