registries_file="/etc/containers/registries.conf"
current_registries="$(sed -n '/registries.insecure/{n; s/registries = //p}' "$registries_file" | tr -d '[]')"
echo "INFO: old registries are $current_registries"
changed_registries=""
[ -n "$current_registries" ] && changed_registries+="$current_registries"

container_registry=$(echo $CONTAINER_REGISTRY | cut -d '/' -f1)
if [[ -n "$container_registry"  ]] && [[ ${changed_registries} != *"$container_registry"* ]] && is_registry_insecure "$container_registry" ; then
       echo "INFO: adding CONTAINER_REGISTRY into insecure registry $container_registry"
       changed_registries+="'$container_registry'"
fi

container_registry=$(echo $DEPLOYER_CONTAINER_REGISTRY | cut -d '/' -f1)
if [[ -n "$container_registry"  ]] && [[ ${changed_registries} != *"$container_registry"* ]] && is_registry_insecure "$container_registry" ; then
       echo "INFO: adding DEPLOYER_CONTAINER_REGISTRY insecure registry $container_registry"
       changed_registries+="'$container_registry'"
fi

openstack_container_registry=$(echo $OPENSTACK_CONTAINER_REGISTRY | cut -d '/' -f1)
if [[ -n "$openstack_container_registry" ]] && [[ ${changed_registries} != *"$openstack_container_registry"* ]] && is_registry_insecure "$openstack_container_registry" ; then
    echo "INFO: adding OPENSTACK_CONTAINER_REGISTRY insecure registry $openstack_container_registry"
    changed_registries+="'$openstack_container_registry'"
fi

if [ "$current_registries" != "$changed_registries" ]; then
    changed_registries=$(echo "$changed_registries" | sed "s/''/', '/g")
    changed_registries="registries = [$changed_registries]"
    echo "INFO: new registries are $changed_registries"
    sudo sed "/registries.insecure/{n; s/registries = .*$/${changed_registries}/g}" ${registries_file} > registries.conf.tmp
    sudo mv registries.conf.tmp ${registries_file}
fi
