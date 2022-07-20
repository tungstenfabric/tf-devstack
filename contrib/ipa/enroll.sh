#!/bin/bash -ex

IPA_IP=$1
IPA_PRINCIPAL=$2
IPA_PASSWORD=$3
HOST_IP=$4
CA_DIR=/etc/contrail/ssl/ca-certs
CERTS_DIR=/etc/contrail/ssl/certs

export DISTRO=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
export DISTRO_VERSION_ID=$(cat /etc/*release | egrep '^VERSION_ID=' | awk -F= '{print $2}' | tr -d \")

sudo mkdir -p $CA_DIR
sudo mkdir -p $CERTS_DIR

#Managing SeLinux policies for directories
sudo semanage fcontext -a -t cert_t "$CERTS_DIR(/.*)?"
sudo restorecon -rv "$CERTS_DIR"
sudo semanage fcontext -a -t cert_t "$CA_DIR(/.*)?"
sudo restorecon -rv "$CA_DIR"
ls -laZ $CA_DIR $CERTS_DIR

sudo yum install -y bind-utils
sudo sed -i.bak "s/\(nameserver\) .*/\1 $IPA_IP/" /etc/resolv.conf

IPA_FQDN=$(nslookup "$IPA_IP" | grep name | awk '{print $4}' | rev | cut -c 2- | rev)
IPA_DOMAIN=$(echo "$IPA_FQDN" | cut -d "." -f 2-)
PTR_ZONE=$(echo "$HOST_IP" | awk -F. '{print $3"."$2"."$1}').in-addr.arpa

HOST_FQDN="$(hostname -s | cut -d '.' -f1).${IPA_DOMAIN}"
if [[ "$(hostname -f)" != "$HOST_FQDN" ]] ; then
    sudo hostnamectl set-hostname "$HOST_FQDN"
fi

if [[ "$DISTRO" == "rhel" && "$DISTRO_VERSION_ID" =~ ^8\. ]]; then
    sudo yum module install -y idm
    #sudo yum module enable idm:DL1
    sudo yum distro-sync -y
    #sudo yum module install -y idm:DL1/client
    #sudo ipa-client-install --enable-dns-updates --mkhomedir
else
    sudo yum install ipa-client -y
fi

sudo ipa-client-install --verbose -U --server "$IPA_FQDN" -p "$IPA_PRINCIPAL" -w "$IPA_PASSWORD" --domain "$IPA_DOMAIN" --hostname "$HOST_FQDN" || error_code=$?
if [[ $error_code == 3 ]] ; then
    echo "The client is already configured"
elif [[ -n $error_code ]] ; then
    exit 1
fi

sudo cp /etc/ipa/ca.crt $CA_DIR/ca-bundle.crt

echo "$IPA_PASSWORD" | sudo kinit "$IPA_PRINCIPAL"

sudo ipa dnszone-find "$PTR_ZONE" || sudo ipa dnszone-add "$PTR_ZONE"
sudo ipa dnsrecord-find "$PTR_ZONE" --ptr-rec "$HOST_FQDN". || sudo ipa dnsrecord-add "$PTR_ZONE" "$(echo "$HOST_IP" | awk -F. '{print $4}')" --ptr-rec "$HOST_FQDN".
sudo ipa dnsrecord-find --name="$Hostname" "$IPA_DOMAIN" || sudo ipa dnsrecord-add --a-ip-address="$HOST_IP" "$IPA_DOMAIN" "$Hostname"

HOST_PRINCIPAL=contrail/"$HOST_FQDN"@"${IPA_DOMAIN^^}"

if ! sudo ipa service-find "$HOST_PRINCIPAL" ; then
    sudo ipa service-add "$HOST_PRINCIPAL" || true
    sudo ipa service-add-host --hosts "$HOST_FQDN" "$HOST_PRINCIPAL" || true
fi

res=1
if [ ! -e $CERTS_DIR/client-"$HOST_IP".crt ] ; then
    sudo ipa-getcert request -f $CERTS_DIR/client-"$HOST_IP".crt -k $CERTS_DIR/client-key-"$HOST_IP".pem -D "$HOST_FQDN" -K contrail/"$HOST_FQDN"@"${IPA_DOMAIN^^}"
    for i in {1..30} ; do
        echo "INFO: waiting for $CERTS_DIR/client-"$HOST_IP".crt to appear. Try $i from 30"
        if [ -e $CERTS_DIR/client-"$HOST_IP".crt ] ; then
            echo "INFO: $CERTS_DIR/client-"$HOST_IP".crt found"
            res=0
            break
        fi
        sleep 2
    done
fi

if [[ $res == 1 ]]; then
    echo "INFO: sudo ipa-getcert request $CERTS_DIR/client-"$HOST_IP".crt failed. Exit"
    exit 1
fi

res=1
if [ ! -e $CERTS_DIR/server-"$HOST_IP".crt ] ; then
    sudo ipa-getcert request -f $CERTS_DIR/server-"$HOST_IP".crt -k $CERTS_DIR/server-key-"$HOST_IP".pem -D "$HOST_FQDN" -K contrail/"$HOST_FQDN"@"${IPA_DOMAIN^^}"
    for i in {1..30} ; do
        echo "INFO: waiting for $CERTS_DIR/server-"$HOST_IP".crt to appear. Try $i from 30"
        if [ -e $CERTS_DIR/server-"$HOST_IP".crt ] ; then
            echo "INFO: $CERTS_DIR/server-"$HOST_IP".crt found"
            res=0
            break
        fi
        sleep 2
    done
fi

if [[ $res == 1 ]]; then
    echo "INFO: sudo ipa-getcert request failed $CERTS_DIR/server-"$HOST_IP".crt. Exit"
    exit 1
fi

sudo chmod -R a+rX $CA_DIR
sudo chmod -R a+rX $CERTS_DIR
