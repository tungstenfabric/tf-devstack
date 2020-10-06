

export IPMI_PASSWORD=${IPMI_PASSWORD}

export SSH_USER=${SSH_USER}

export ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no"

export CONFIGURE_DOCKER_LIVERESTORE='false'

#IP, subnets
export mgmt_subnet=${mgmt_subnet}
export mgmt_gateway=${mgmt_gateway}
#Undercloud mgmt ip
export mgmt_ip=${mgmt_ip}

export prov_cidr=${prov_cidr}
export prov_subnet_len=${prov_subnet_len}

export prov_subnet=${prov_subnet}
export prov_gateway=${prov_gateway}
export prov_inspection_iprange=${prov_inspection_iprange}
export prov_dhcp_start=${prov_dhcp_start}
export prov_dhcp_end=${prov_dhcp_end}

#Undercloud prov ip
export prov_ip=${prov_ip}
export prov_ip_cidr=${prov_ip_cidr}

export fixed_vip=${fixed_vip}
export fixed_controller_ip=${fixed_controller_ip}

#Undecloud
export undercloud_instance=${undercloud_instance}
export domain=${domain}

#RHOSP16 additional parameters for undercloud.conf
export undercloud_admin_host="${undercloud_admin_host}"
export undercloud_public_host="${undercloud_public_host}"

#Prov IPs for overcloud nodes
export overcloud_cont_prov_ip=${overcloud_cont_prov_ip}
export overcloud_compute_prov_ip=${overcloud_compute_prov_ip}
export overcloud_ctrlcont_prov_ip=${overcloud_ctrlcont_prov_ip}

export overcloud_cont_instance=${overcloud_cont_instance}
export overcloud_compute_instance=${overcloud_compute_instance}
export overcloud_ctrlcont_instance=${overcloud_ctrlcont_instance}
