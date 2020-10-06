#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

#BASE_IMAGE="/home/ubuntu/rhel-7.7.qcow2"

cd
source rhosp-environment.sh
source $my_dir/virsh_functions

# collect MAC addresses of overcloud machines
function get_macs() {
  local name=$1
  truncate -s 0 /tmp/nodes-$name.txt
  sudo virsh domiflist $name | awk '$3 ~ "prov" {print $5};'
}

function get_vbmc_ip() {
  local name=$1
  call_vbmc list | grep $name | awk -F\| '{print $4}'
}

function get_vbmc_port() {
  local name=$1
  call_vbmc list | grep $name | awk -F\| '{print $5}'
}

function define_machine() {
  local caps=$1
  local mac=$2
  local pm_ip=$3
  local pm_port=$4
  cat << EOF >> instackenv.json
    {
      "pm_type": "pxe_ipmitool",
      "pm_addr": "$pm_ip",
      "pm_port": "$pm_port",
      "pm_user": "$IPMI_USER",
      "pm_password": "$IPMI_PASSWORD",
      "mac": [
        "$mac"
      ],
      "cpu": "2",
      "memory": "1000",
      "disk": "29",
      "arch": "x86_64",
      "capabilities": "$caps"
    },
EOF
}

# create overcloud machines definition
cat << EOF > instackenv.json
{
  "power_manager": "nova.virt.baremetal.virtual_power_driver.VirtualPowerManager",
  "arch": "x86_64",
  "nodes": [
EOF

unset vbmc_ip
unset vbmc_port
unset mac

node_type=controller
for node in $(echo $overcloud_cont_instance | sed 's/,/ /g') ; do
  vbmc_ip=$(get_vbmc_ip $node)
  vbmc_port=$(get_vbmc_port $node)
  mac=$(get_macs $node)
  define_machine "profile:${node_type},boot_option:local" $mac $vbmc_ip $vbmc_port
done

node_type=compute
for node in $(echo $overcloud_compute_instance | sed 's/,/ /g') ; do
  vbmc_ip=$(get_vbmc_ip $node)
  vbmc_port=$(get_vbmc_port $node)
  mac=$(get_macs $node)
  define_machine "profile:${node_type},boot_option:local" $mac $vbmc_ip $vbmc_port
done

node=$overcloud_ctrlcont_instance
node_type=contrail-controller
vbmc_ip=$(get_vbmc_ip $node)
vbmc_port=$(get_vbmc_port $node)
mac=$(get_macs $node)
define_machine "profile:${node_type},boot_option:local" $mac $vbmc_ip $vbmc_port

# remove last comma
head -n -1 instackenv.json > instackenv.json.tmp
mv instackenv.json.tmp instackenv.json
cat << EOF >> instackenv.json
    }
  ]
}
EOF

# check this json (it's optional)
# curl --silent -O https://raw.githubusercontent.com/rthallisey/clapper/master/instackenv-validator.py
# python3 instackenv-validator.py -f ~/instackenv.json



