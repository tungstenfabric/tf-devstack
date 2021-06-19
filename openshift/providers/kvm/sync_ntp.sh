#!/bin/bash -e

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"
source "$my_dir/../../../common/common.sh"
source "$my_dir/../../../common/functions.sh"
source $my_dir/definitions

# NB. skip lb and bootstrap items
netw=$(echo $VIRTUAL_NET | cut -d ',' -f 1)
sync_time core $(sudo virsh net-dumpxml $netw | xmllint --xpath '/network/ip/dhcp/host/@ip' - | sed 's| ip=|\nip=|g' | sed '/^$/d;$a\' | tail -n +3 | while read x; do eval $x; echo $ip; done)
