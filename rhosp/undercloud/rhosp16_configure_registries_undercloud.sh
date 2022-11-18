#Configuring insecure registries for podman
for registry in "$CONTAINER_REGISTRY" "$DEPLOYER_CONTAINER_REGISTRY" "$OPENSTACK_CONTAINER_REGISTRY"; do
    container_registry=$(echo $registry | cut -d '/' -f1)
    if [[ "$container_registry" != "" ]] && is_registry_insecure "$container_registry"; then
        configure_podman_insecure_registries $container_registry
    fi
done


