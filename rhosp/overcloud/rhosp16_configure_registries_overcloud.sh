if [ -n "$CONTAINER_REGISTRY" ] && is_registry_insecure $CONTAINER_REGISTRY ; then
    registries_file="/etc/containers/registries.conf"
    current_registries="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$registries_file" | tr -d '[]')"
    changed_registries="[$current_registries,'$CONTAINER_REGISTRY']"
    echo "INFO: new registries are $changed_registries"
    sed -i "/registries.insecure/{n; s/registries = .*$/${changed_registries}/g}" ${registries_file}
fi
