if [[ -n "$CONTAINER_REGISTRY" ]] ; then
    registries_file="/etc/containers/registries.conf"
    current_registries="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$registries_file" | tr -d '[]')"
    changed_registries="[$current_registries,'$CONTAINER_REGISTRY']"
    [ -n "$OPENSTACK_CONTAINER_REGISTRY" ] && changed_registries="[$current_registries,'$CONTAINER_REGISTRY', '$OPENSTACK_CONTAINER_REGISTRY']"
    echo "INFO: new registries are $changed_registries"
    sudo sed "/registries.insecure/{n; s/registries = .*$/${changed_registries}/g}" ${registries_file} > ${registries_file}.temp
    sudo cp -f ${registries_file}.temp ${registries_file}
    rm -rf ${registries_file}.temp
fi