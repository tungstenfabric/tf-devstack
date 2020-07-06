CONTAINER_REGISTRY="" CONFIGURE_DOCKER_LIVERESTORE=false ./create_docker_config.sh
insecure_registries=$(cat /etc/sysconfig/docker | awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' | tr -d '"')
if ! echo "$insecure_registries" | grep -q "${prov_ip}:8787" ; then
   insecure_registries+=" --insecure-registry ${prov_ip}:8787"
   [ -n "$OPENSTACK_CONTAINER_REGISTRY" ] && insecure_registries+=" --insecure-registry $OPENSTACK_CONTAINER_REGISTRY"
   sed -i '/^INSECURE_REGISTRY/d' /etc/sysconfig/docker
   echo "INSECURE_REGISTRY=\"$insecure_registries\"" | tee -a /etc/sysconfig/docker
fi

if ! systemctl restart docker ; then
   systemctl status docker.service
   journalctl -xe
   exit 1
fi