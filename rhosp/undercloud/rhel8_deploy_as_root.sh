
#RHEL8 undercloud install

#removing docker-ce package to avoid conflicts with podman
dnf remove -y docker-ce-cli

dnf install -y python3-tripleoclient rhosp-director-images rhosp-director-images-ipa
