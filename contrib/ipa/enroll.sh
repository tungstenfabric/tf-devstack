#!/bin/bash -e

IPA_IP=$1
IPA_PRINCIPAL=$2
IPA_PASSWORD=$3
HOST_IP=$4
CA_DIR=/etc/contrail/ssl/ca-certs
CERTS_DIR=/etc/contrail/ssl/certs

sudo mkdir -p $CA_DIR
sudo mkdir -p $CERTS_DIR

sudo sed -i.bak "s/\(nameserver\) .*/\1 $IPA_IP/" /etc/resolv.conf

IPA_FQDN=$(nslookup "$IPA_IP" | grep name | awk '{print $4}' | rev | cut -c 2- | rev)
IPA_DOMAIN=$(echo "$IPA_FQDN" | cut -d "." -f 2-)
PTR_ZONE=$(echo "$HOST_IP" | awk -F. '{print $3"."$2"."$1}').in-addr.arpa

HOST_FQDN="$(hostname -s | cut -d '.' -f1).${IPA_DOMAIN}"
if [[ "$(hostname -f)" != "$HOST_FQDN" ]] ; then
    sudo hostnamectl set-hostname "$HOST_FQDN"
fi

sudo yum install ipa-client -y
sudo ipa-client-install --verbose -U --server "$IPA_FQDN" -p "$IPA_PRINCIPAL" -w "$IPA_PASSWORD" --domain "$IPA_DOMAIN" --hostname "$HOST_FQDN"

sudo cp /etc/ipa/ca.crt $CA_DIR/ca-bundle.crt

echo "$IPA_PASSWORD" | kinit "$IPA_PRINCIPAL"

sudo ipa dnszone-find "$PTR_ZONE" || sudo ipa dnszone-add "$PTR_ZONE"
sudo ipa dnsrecord-find "$PTR_ZONE" --ptr-rec "$HOST_FQDN". || sudo ipa dnsrecord-add "$PTR_ZONE" "$(echo "$HOST_IP" | awk -F. '{print $3}')" --ptr-rec "$HOST_FQDN".
sudo ipa dnsrecord-find --name="$Hostname" "$IPA_DOMAIN" || sudo ipa dnsrecord-add --a-ip-address="$HOST_IP" "$IPA_DOMAIN" "$Hostname"

HOST_PRINCIPAL=contrail/"$HOST_FQDN"@"${IPA_DOMAIN^^}"

if ! ipa service-find "$HOST_PRINCIPAL" ; then
    sudo ipa service-add "$HOST_PRINCIPAL"
    sudo ipa service-add-host --hosts "$HOST_FQDN" "$HOST_PRINCIPAL"
fi
if [ ! -e $CERTS_DIR/client-"$HOST_IP".crt ] ; then
    sudo ipa-getcert request -f $CERTS_DIR/client-"$HOST_IP".crt -k $CERTS_DIR/client-key-"$HOST_IP".pem -D "$HOST_FQDN" -A "$HOST_IP" -K contrail/"$HOST_FQDN"@"${IPA_DOMAIN^^}"
    while [ ! -e $CERTS_DIR/client-"$HOST_IP".crt ] ; do sleep 1; done
fi

if [ ! -e $CERTS_DIR/server-"$HOST_IP".crt ] ; then
    sudo ipa-getcert request -f $CERTS_DIR/server-"$HOST_IP".crt -k $CERTS_DIR/server-key-"$HOST_IP".pem -D "$HOST_FQDN" -A "$HOST_IP" -K contrail/"$HOST_FQDN"@"${IPA_DOMAIN^^}"
    while [ ! -e $CERTS_DIR/server-"$HOST_IP".crt ] ; do sleep 1; done
fi

sudo chmod -R a+rX $CA_DIR
sudo chmod -R a+rX $CERTS_DIR
