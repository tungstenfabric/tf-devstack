#!/bin/sh



#Password for user stack
export IPMI_PASSWORD="qwe123QWE"

export SSH_USER='cloud-user'
export SSH_PUBLIC_KEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqFitjdvlQlaVJ8oBTkm3Qt48XCNh8ikbYN38WofGJk5oGXtC35H9eBBJ8giv42Lw4JXzBmVSEceMPEmTnIM3JPEhl/uNgn+Y+0e+pInq6bt3+DjjZxLvhun7G3LP8RgwYMvMWUkNEHnwLaCKipjfzrPkp0uD/1ZQVjY799gSyDX2PylneiLNSSWQxvOwNe8dzLyVTxlS2jFzNmMX5I5a9/z2Dw9PTB8FdFQbAKc7ZqaiYBrp3kaTcBlQh2pRpKEGGhosKhp4DPHoQV/f3myfl3sAZNGfpbFLzBxLyY/nHIJ3w2AsWahxKnxdGSxhmmp5KJ6zl4+OhJdNZEb2glK2l gleb@dell'

#SSH public key for user
export ssh_private_key="/home/jenkins/.ssh/id_rsa"
export ssh_public_key="/home/jenkins/.ssh/id_rsa.pub"

#IP, subnets
export mgmt_subnet="192.168.10"
export mgmt_gateway="${mgmt_subnet}.1"
export mgmt_ip="${mgmt_subnet}.112"

export prov_subnet="192.168.12"
export prov_gateway="${prov_subnet}.1"
export prov_ip="${prov_subnet}.36"

export fixed_vip="${prov_subnet}.200"
export fixed_controller_ip="${prov_subnet}.211"

export overcloud_cont_prov_ip="${prov_subnet}.40"
export overcloud_compute_prov_ip="${prov_subnet}.9"
export overcloud_ctrlcont_prov_ip="${prov_subnet}.48"


export CONTRAIL_VERSION="5.1"

