#removing docker-ce package to avoid conflicts with podman
sudo dnf remove -y docker-ce-cli || true

# fix module otherwise upstream usage leads to packages conflicts
sudo dnf module disable -y container-tools idm
sudo dnf module enable -y container-tools:2.0 idm:DL1
sudo dnf distro-sync -y 

sudo dnf update -y

packages="chrony wget yum-utils vim iproute jq curl bind-utils network-scripts net-tools tmux createrepo bind-utils sshpass python36 python3-pip python3-virtualenv podman"
[[ "$ENABLE_TLS" != 'ipa' ]] || packages+=" ipa-client python3-novajoin"

sudo dnf install -y --allowerasing $packages

sudo systemctl start chronyd

sudo alternatives --set python /usr/bin/python3
