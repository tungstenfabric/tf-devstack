

source $my_dir/providers/kvm/virsh_functions

# delete stack to unregister nodes
# unregister undercloud & overcloud
ssh $ssh_opts $SSH_USER@${instance_ip} "ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION ./tf-devstack/rhosp/providers/common/cleanup.sh"

if [[ "$ENABLE_TLS" == 'ipa' ]] ; then
    ssh $ssh_opts $SSH_USER@${ipa_mgmt_ip} "sudo subscription-manager unregister" || true
fi

function delete_node() {
    local name=$1
    local disk=$2
    local pool=${3:-"$poolname"}

    delete_domain $name
    delete_volume "$disk" $pool
}

for i in $(echo $overcloud_cont_instance $overcloud_compute_instance $overcloud_ctrlcont_instance $undercloud_instance $ipa_instance | sed 's/,/ /g') ; do
    delete_node $i "$i.qcow2" 
done

delete_network_dhcp $NET_NAME_MGMT
delete_network_dhcp $NET_NAME_PROV

sudo virsh pool-destroy $poolname
sudo virsh pool-undefine $poolname
