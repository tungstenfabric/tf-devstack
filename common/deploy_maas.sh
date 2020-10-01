#!/bin/bash
set -o errexit
set -o pipefail

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"
source "$my_dir/functions.sh"

# Install MAAS and tools
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update -y
sudo -E apt-get install snapd jq prips netmask -y
sudo -E snap install maas

# hack it.
# for some reasons MAAS sends manage_etc_hosts as True to cloud-init
# and cloud-init adds strange item '127.0.1.1 hostname fqdn' to /etc/hosts
# this items looks useless and config-api can't talk to keystone due to this.
# change cloud-init settings is available via 'maas deploy' but we use juju
# to deploy machines and I didn't found a way how to pass clou-init data
# via juju's bundle.
# therefore - using hacking method.
sudo cp -R /snap/maas/current/lib/python3.6/site-packages/maasserver /tmp
sudo sed -i 's/"manage_etc_hosts": True/"manage_etc_hosts": False/' /tmp/maasserver/compose_preseed.py
sudo mount --bind -o nodev,ro /tmp/maasserver /snap/maas/current/lib/python3.6/site-packages/maasserver
sudo systemctl restart snap.maas.supervisor.service

# Determined variables
NODE_IP_WSUBNET=`ip addr show dev $PHYS_INT | grep 'inet ' | awk '{print $2}' | head -n 1`
NODE_SUBNET=`netmask $NODE_IP_WSUBNET`
readarray -t SUBNET_IPS <<< "$(prips $NODE_SUBNET)"

# MAAS variables
MAAS_ADMIN=${MAAS_ADMIN:-"admin"}
MAAS_PASS=${MAAS_PASS:-"admin"}
MAAS_ADMIN_MAIL=${MAAS_ADMIN_MAIL:-"admin@maas.tld"}
UPSTREAM_DNS=${UPSTREAM_DNS:-"8.8.8.8"}
DHCP_RESERVATION_IP_START=${DHCP_RESERVATION_IP_START:-`echo ${SUBNET_IPS[@]:(-64):1}`}
DHCP_RESERVATION_IP_END=${DHCP_RESERVATION_IP_END:-`echo ${SUBNET_IPS[@]:(-2):1}`}
export VIRTUAL_IPS=$(prips $NODE_SUBNET | grep -P "^${DHCP_RESERVATION_IP_START}$"  -A6 | tr '\n' ' ' )

# Nodes for commissioning
IPMI_POWER_DRIVER=${IPMI_POWER_DRIVER:-"LAN_2_0"}
IPMI_IPS=${IPMI_IPS:-""}
IPMI_USER=${IPMI_USER:-"ADMIN"}
IPMI_PASS=${IPMI_PASS:-"ADMIN"}

# MAAS init
sudo maas init --mode all \
    --maas-url "http://${NODE_IP}:5240/MAAS" \
    --admin-username "${MAAS_ADMIN}" \
    --admin-password "${MAAS_PASS}" \
    --admin-email "${MAAS_ADMIN_MAIL}"

# login
export PATH="$PATH:/snap/bin"
PROFILE="${MAAS_ADMIN}"
export MAAS_ENDPOINT="http://${NODE_IP}:5240/MAAS"
export MAAS_API_KEY=$(sudo maas apikey --username="$PROFILE")
maas login $PROFILE $MAAS_ENDPOINT - <<< $(echo $MAAS_API_KEY)

# Add public key to user "admin"
set_ssh_keys
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
maas $PROFILE sshkeys create "key=$SSH_KEY"

# Configure dns
maas $PROFILE maas set-config name=upstream_dns value=$UPSTREAM_DNS

# Configure dhcp
maas $PROFILE ipranges create type=dynamic \
    start_ip=${DHCP_RESERVATION_IP_START} end_ip=${DHCP_RESERVATION_IP_END}
maas $PROFILE vlan update 0 0 dhcp_on=True primary_rack=$(hostname)

# Import images.
# Import may fail without any error messages, loop is workaround.
for ((i=0; i<30; ++i)); do
  maas $PROFILE boot-resources import
  sleep 15
  if maas $PROFILE boot-resources read | grep -q "ga-18.04"; then
    break
  fi
done

# Waiting for images download to complete
for ((i=0; i<60; ++i)); do
  if maas $PROFILE boot-resources is-importing | grep -q 'false'; then
    sleep 60
    break
  fi
  sleep 20
done
if ! maas $PROFILE boot-resources is-importing | grep -q 'false' ; then
  echo "Images not ready."
  maas $PROFILE boot-resources is-importing
  exit 1
fi

# Add machines
for n in $IPMI_IPS ; do
  maas $PROFILE machines create \
      architecture="amd64/generic" \
      hwe_kernel="ga-18.04" \
      power_type="ipmi" \
      power_parameters_power_driver=${IPMI_POWER_DRIVER} \
      power_parameters_power_user=${IPMI_USER} \
      power_parameters_power_pass=${IPMI_PASS} \
      power_parameters_power_address=${n}
done

sleep 180
for ((i=0; i<30; ++i)); do
  MACHINES_STATUS=`maas $PROFILE machines read | jq -r '.[].status_name'`
  MACHINES_COUNT=`echo "$MACHINES_STATUS" | wc -l`
  if echo "$MACHINES_STATUS" | grep -q "Ready"; then
    READY_COUNT=`echo "$MACHINES_STATUS" | grep -c "Ready"`
    if [[ $READY_COUNT == $MACHINES_COUNT ]]; then
      break
    fi
  fi
  sleep 30
done
if [[ $READY_COUNT != $MACHINES_COUNT ]]; then
  echo "ERROR: timeout for commissioning exceeded. Machines were not created properly"
  exit 1
fi

if [ -n "$1" ]; then
  echo "export MAAS_ENDPOINT=\"$MAAS_ENDPOINT\"" >> "$1"
  echo "export MAAS_API_KEY=\"$MAAS_API_KEY\"" >> "$1"
  echo "export VIRTUAL_IPS=\"$VIRTUAL_IPS\"" >> "$1"
fi

echo "INFO: MAAS is ready "
echo "INFO: MAAS web ui $MAAS_ENDPOINT"
echo "Set variables to use with juju deployment:"
echo "export MAAS_ENDPOINT=\"$MAAS_ENDPOINT\""
echo "export MAAS_API_KEY=\"$MAAS_API_KEY\""
echo "export VIRTUAL_IPS=\"$VIRTUAL_IPS\""
