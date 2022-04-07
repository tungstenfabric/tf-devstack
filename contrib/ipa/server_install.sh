#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Exactly 1 arguments required"
    echo "Usage: $1 <IPA PASSWORD>"
fi

IPAPASSWORD=$2

sudo yum install -y ipa-server ipa-server-dns
sudo ipa-server-install -U -r `hostname -d|tr "[a-z]" "[A-Z]"` \
                    -p $IPAPASSWORD -a $IPAPASSWORD \
                    --hostname $(hostname -f) \
                    --ip-address=$(hostname -i) \
                    --setup-dns --auto-forwarders --auto-reverse
