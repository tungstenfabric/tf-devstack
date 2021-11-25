#removing docker-ce package to avoid conflicts with podman
sudo dnf remove -y docker-ce-cli || true

# fix module otherwise upstream usage leads to packages conflicts
echo "INFO: dnf disable modules container-tools idm"
sudo dnf module disable -y container-tools idm || true

declare -A _dnf_container_tools=(
  ["rhel8.2"]="container-tools:2.0"
  ["rhel8.4"]="container-tools:3.0"
)
_ctools=${_dnf_container_tools[$RHEL_VERSION]}
if [ -z "$_ctools" ] ; then
  echo "ERROR: internal error - no container-tools set for $RHEL_VERSION"
  exit 1
fi
echo "INFO: dnf enable $_ctools"
sudo dnf module enable -y $_ctools

echo "INFO: dnf enable idm:DL1"
sudo dnf module enable -y idm:DL1

#Fix for ceph-storage issue https://access.redhat.com/solutions/5912141
sudo dnf module disable -y virt:rhel || true
#rhel_ver=$(echo $RHEL_VERSION | sed "s/rhel//" )
#sudo dnf module enable -y virt:${rhel_ver}
echo "INFO: enable virt:8.2"
sudo dnf module enable -y virt:8.2

sudo dnf distro-sync -y

sudo dnf update -y

packages="chrony wget yum-utils vim iproute jq curl bind-utils network-scripts net-tools tmux createrepo bind-utils sshpass python36 podman"
[[ "$ENABLE_TLS" != 'ipa' ]] || packages+=" ipa-client python3-novajoin openssl-perl ca-certificates"

sudo dnf install -y --allowerasing $packages

sudo systemctl start chronyd

sudo alternatives --set python /usr/bin/python3
