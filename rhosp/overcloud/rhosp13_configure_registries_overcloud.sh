
sudo CONTAINER_REGISTRY="" CONFIGURE_DOCKER_LIVERESTORE=false $my_dir/../../common/create_docker_config.sh
insecure_registries=$(sudo cat /etc/sysconfig/docker | awk -F '=' '/^INSECURE_REGISTRY=/{print($2)}' | tr -d '"')
if ! echo "$insecure_registries" | grep -q "${prov_ip}:8787" ; then
   insecure_registries+=" --insecure-registry ${prov_ip}:8787"
   sudo sed -i '/^INSECURE_REGISTRY/d' /etc/sysconfig/docker
   echo "INSECURE_REGISTRY=\"$insecure_registries\"" | sudo tee -a /etc/sysconfig/docker
fi

if ! sudo systemctl restart docker ; then
   sudo systemctl status docker.service
   sudo journalctl -xe
   exit 1
fi