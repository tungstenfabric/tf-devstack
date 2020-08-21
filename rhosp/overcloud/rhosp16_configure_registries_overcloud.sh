
registries_file="/etc/containers/registries.conf"
current_registries="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$registries_file" | tr -d '[]')"
echo "INFO: old registries are $current_registries"
changed_registries=""
[ -n "$current_registries" ] && changed_registries+="$current_registries, "
if ! echo "$current_registries" | grep -q "${prov_ip}:8787" ; then
   changed_registries+="'${prov_ip}:8787'"
   changed_registries="registries = [$changed_registries]"
   echo "INFO: new registries are $changed_registries"
   sudo sed "/registries.insecure/{n; s/registries = .*$/${changed_registries}/g}" ${registries_file} > registries.conf.tmp
   sudo mv registries.conf.tmp ${registries_file}
fi
