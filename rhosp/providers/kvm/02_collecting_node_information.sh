#!/bin/bash -ex

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run by root. Please use sudo"
   exit 1
fi


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

#BASE_IMAGE="/home/ubuntu/rhel-7.7.qcow2"

source "/home/$SUDO_USER/rhosp-environment.sh"
cd $my_dir

# collect MAC addresses of overcloud machines
function get_macs() {
  local type=$1
  truncate -s 0 /tmp/nodes-$type.txt
  virsh domiflist rhosp13-overcloud-$type | awk '$3 ~ "prov" {print $5};'
}

function get_vbmc_ip() {
  local type=$1
  vbmc list | grep rhosp13-overcloud-$type | awk -F\| '{print $4}'
}

function get_vbmc_port() {
  local type=$1
  vbmc list | grep rhosp13-overcloud-$type | awk -F\| '{print $5}'
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

declare -A longname=( ["cont"]="controller" ["compute"]="compute" ["ctrlcont"]="contrail-controller" )

unset vbmc_ip
unset vbmc_port
unset mac
for node in 'cont' 'compute' 'ctrlcont'; do
  vbmc_ip=$(get_vbmc_ip $node)
  vbmc_port=$(get_vbmc_port $node)
  mac=$(get_macs $node)
  define_machine "profile:${longname[$node]},boot_option:local" $mac $vbmc_ip $vbmc_port
done

# remove last comma
head -n -1 instackenv.json > instackenv.json.tmp
mv instackenv.json.tmp instackenv.json
cat << EOF >> instackenv.json
    }
  ]
}
EOF

mv instackenv.json /home/$SUDO_USER/

# check this json (it's optional)
#curl --silent -O https://raw.githubusercontent.com/rthallisey/clapper/master/instackenv-validator.py
#python instackenv-validator.py -f ~/instackenv.json


