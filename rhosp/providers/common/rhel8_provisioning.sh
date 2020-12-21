#removing docker-ce package to avoid conflicts with podman
sudo dnf remove -y docker-ce-cli || true

# fix module otherwise upstream usage leads to packages conflicts
sudo dnf module disable -y container-tools idm
sudo dnf module enable -y container-tools:2.0 idm:DL1

#Set release to prevent upgrade to 8.3 (Tripleo supports only 8.2)
if [[ "$PROVIDER" == 'kvm' && "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
   sudo subscription-manager release --set=8.2
fi

sudo dnf distro-sync -y 

sudo dnf update -y

packages="chrony wget yum-utils vim iproute jq curl bind-utils network-scripts net-tools tmux createrepo bind-utils sshpass python36 podman"
[[ "$ENABLE_TLS" != 'ipa' ]] || packages+=" ipa-client python3-novajoin openssl-perl ca-certificates"

sudo dnf install -y --allowerasing $packages

sudo systemctl start chronyd

sudo alternatives --set python /usr/bin/python3
