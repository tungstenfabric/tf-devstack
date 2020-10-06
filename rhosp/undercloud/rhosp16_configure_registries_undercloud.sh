registries_file="/etc/containers/registries.conf"
current_registries="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$registries_file" | tr -d '[]')"
echo "INFO: old registries are $current_registries"
changed_registries=""
[ -n "$current_registries" ] && changed_registries+="$current_registries"
if [[ -n "$CONTAINER_REGISTRY"  ]] && is_registry_insecure "$CONTAINER_REGISTRY" ; then
    changed_registries+="'$CONTAINER_REGISTRY'"
fi
if [[ -n "$OPENSTACK_CONTAINER_REGISTRY" ]]  && is_registry_insecure "$OPENSTACK_CONTAINER_REGISTRY" ; then
    changed_registries+="'$OPENSTACK_CONTAINER_REGISTRY'"
fi

if [ "$current_registries" != "$changed_registries" ]; then
    changed_registries=$(echo "$changed_registries" | sed "s/''/', '/g")
    changed_registries="registries = [$changed_registries]"
    echo "INFO: new registries are $changed_registries"
    sudo sed "/registries.insecure/{n; s/registries = .*$/${changed_registries}/g}" ${registries_file} > registries.conf.tmp
    sudo mv registries.conf.tmp ${registries_file}
fi
