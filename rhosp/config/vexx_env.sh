

export IPMI_PASSWORD=${IPMI_PASSWORD:-"qwe123QWE"}

export SSH_USER=${SSH_USER:-'cloud-user'}
#export SSH_PUBLIC_KEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqFitjdvlQlaVJ8oBTkm3Qt48XCNh8ikbYN38WofGJk5oGXtC35H9eBBJ8giv42Lw4JXzBmVSEceMPEmTnIM3JPEhl/uNgn+Y+0e+pInq6bt3+DjjZxLvhun7G3LP8RgwYMvMWUkNEHnwLaCKipjfzrPkp0uD/1ZQVjY799gSyDX2PylneiLNSSWQxvOwNe8dzLyVTxlS2jFzNmMX5I5a9/z2Dw9PTB8FdFQbAKc7ZqaiYBrp3kaTcBlQh2pRpKEGGhosKhp4DPHoQV/f3myfl3sAZNGfpbFLzBxLyY/nHIJ3w2AsWahxKnxdGSxhmmp5KJ6zl4+OhJdNZEb2glK2l jenkins@slave'

#IP, subnets
export mgmt_subnet=${mgmt_subnet:-"192.168.10"}
export mgmt_gateway=${mgmt_gateway:-"${mgmt_subnet}.1"}
#Undercloud mgmt ip
export mgmt_ip=${mgmt_ip:-"${mgmt_subnet}.112"}

export prov_subnet=${prov_subnet:-"192.168.12"}
export prov_gateway=${prov_gateway:-"${prov_subnet}.1"}

#Undercloud prov ip
export prov_ip=${prov_ip:-"${prov_subnet}.36"}

export fixed_vip=${fixed_vip:-"${prov_subnet}.200"}
export fixed_controller_ip=${fixed_controller_ip:-"${prov_subnet}.211"}

#Undecloud
export undercloud_instance=${undercloud_instance:-"undercloud-${DEPLOY_POSTFIX}"}
export domain=${domain:-'vexxhost.local'}

#Prov IPs for overcloud nodes
export overcloud_cont_prov_ip=${overcloud_cont_prov_ip:-"${prov_subnet}.40"}
export overcloud_compute_prov_ip=${overcloud_compute_prov_ip:-"${prov_subnet}.9"}
export overcloud_ctrlcont_prov_ip=${overcloud_ctrlcont_prov_ip:-"${prov_subnet}.48"}

export overcloud_cont_instance=${overcloud_cont_instance:-"$RHOSP_VERSION-overcloud-cont-${DEPLOY_POSTFIX}"}
export overcloud_compute_instance=${overcloud_compute_instance:-"$RHOSP_VERSION-overcloud-compute-${DEPLOY_POSTFIX}"}
export overcloud_ctrlcont_instance=${overcloud_ctrlcont_instance:-"$RHOSP_VERSION-overcloud-ctrlcont-${DEPLOY_POSTFIX}"}

