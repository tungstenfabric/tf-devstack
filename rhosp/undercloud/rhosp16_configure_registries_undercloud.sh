registries_file="/etc/containers/registries.conf"
current_registries="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$registries_file" | tr -d '[]')"
echo "INFO: old registries are $current_registries"
changed_registries=""
[ -n "$current_registries" ] && changed_registries+="$current_registries "
if [[ -n "$CONTAINER_REGISTRY" && is_insecure_registry "$CONTAINER_REGISTRY" ]] ; then
    changed_registries+="'$CONTAINER_REGISTRY' "
fi
if [[ -n "$OPENSTACK_CONTAINER_REGISTRY" && is_insecure_registry "$OPENSTACK_CONTAINER_REGISTRY" ]] ; then
    changed_registries="'$OPENSTACK_CONTAINER_REGISTRY' "
fi
changed_registries=$(echo "[$changed_registries]" | sed 's/ /,/g')
echo "INFO: new registries are $changed_registries"
sudo sed "/registries.insecure/{n; s/registries = .*$/${changed_registries}/g}" ${registries_file} > registries.conf.tmp
sudo cp -f registries.conf.tmp ${registries_file}
rm -rf registries.conf.tmp
