#!/bin/bash -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
"$my_dir/../ansible/run.sh"

pip3 install contrail-api-client future six

my_fq_name="['default-global-system-config', 'default-global-vrouter-config']"
encap_before_test=$(python3 get_encap_priority.py $HOSTNAME $my_fq_name)

default_encap_priority="encapsulation = ['MPLSoUDP', 'MPLSoGRE', 'VXLAN']"
if [[ $encap_before_test != $default_encap_priority ]] ; then
  echo "ERROR: encap_priority is not default"
  return 1
fi

new_encap_priority='["MPLSoUDP"]'
echo $(python3 change_encap_priority.py $HOSTNAME $my_fq_name $new_encap_priority)

# check changes
encap_after_change=$(python3 get_encap_priority.py $HOSTNAME $my_fq_name)
if [[ $encap_before_test == $encap_after_change ]] ; then
  echo "ERROR: encap_priority was not changed by api"
  return 1
fi

# restarting containers
sudo docker restart $(sudo docker ps -q)
# need waiting ?

encap_after_restart=$(python3 get_encap_priority.py $HOSTNAME $my_fq_name)
if [[ $encap_before_test != $encap_after_restart ]] ; then
  echo "ERROR: encap_priority was not reseted after restarting containers"
  return 1
fi

echo "Test apply_default=true: PASSED"
return 0