

export IPMI_PASSWORD=${IPMI_PASSWORD}

export SSH_USER=${SSH_USER}
#export SSH_PUBLIC_KEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqFitjdvlQlaVJ8oBTkm3Qt48XCNh8ikbYN38WofGJk5oGXtC35H9eBBJ8giv42Lw4JXzBmVSEceMPEmTnIM3JPEhl/uNgn+Y+0e+pInq6bt3+DjjZxLvhun7G3LP8RgwYMvMWUkNEHnwLaCKipjfzrPkp0uD/1ZQVjY799gSyDX2PylneiLNSSWQxvOwNe8dzLyVTxlS2jFzNmMX5I5a9/z2Dw9PTB8FdFQbAKc7ZqaiYBrp3kaTcBlQh2pRpKEGGhosKhp4DPHoQV/f3myfl3sAZNGfpbFLzBxLyY/nHIJ3w2AsWahxKnxdGSxhmmp5KJ6zl4+OhJdNZEb2glK2l jenkins@slave'

#IP, subnets
export mgmt_subnet=${mgmt_subnet}
export mgmt_gateway=${mgmt_gateway}
#Undercloud mgmt ip
export mgmt_ip=${mgmt_ip}

export prov_cidr=${prov_cidr}
export prov_subnet_len=${prov_subnet_len}

export prov_subnet=${prov_subnet}
export prov_gateway=${prov_gateway}

#Undercloud prov ip
export prov_ip=${prov_ip}
export prov_ip_cidr=${prov_ip_cidr}

export fixed_vip=${fixed_vip}
export fixed_controller_ip=${fixed_controller_ip}

#Undecloud
export undercloud_instance=${undercloud_instance}
export domain=${domain}

#Prov IPs for overcloud nodes
export overcloud_cont_prov_ip=${overcloud_cont_prov_ip}
export overcloud_compute_prov_ip=${overcloud_compute_prov_ip}
export overcloud_ctrlcont_prov_ip=${overcloud_ctrlcont_prov_ip}

export overcloud_cont_instance=${overcloud_cont_instance}
export overcloud_compute_instance=${overcloud_compute_instance}
export overcloud_ctrlcont_instance=${overcloud_ctrlcont_instance}
