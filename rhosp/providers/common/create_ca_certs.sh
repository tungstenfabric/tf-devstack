#!/bin/bash -xe

CN=${CN:-"$(hostname)"}

FQDNS=${FQDNS:-"$(hostname -f)"}
_default_ips="$(ip a | awk '/inet /{print($2)}' | cut -d '/' -f1 | grep -v '^127.0.0.' | sort -u | xargs)"
IPS=${IPS:-$__default_ips}

OS_CN=${OS_CN:-}
OS_FQDNS=${OS_FQDNS:-}
OS_IPS=${OS_IPS:-}

BITS=${BITS:-2048}

CA_ROOT_CERT=${CA_ROOT_CERT:-}
CA_ROOT_KEY=${CA_ROOT_KEY:-}

VALIDITY_DAYS=${VALIDITY_DAYS:-365}

ssl_working_dir="$(mktemp -d)"

cd $ssl_working_dir

csr_file="server.pem.csr"
openssl_config_file="contrail_openssl.cfg"

mkdir certs
touch index.txt index.txt.attr
echo 1000 >serial.txt

function make_ssl_config() {
  local cn=$1
  local fqdns=$2
  local ips=$3

cat <<EOF > $openssl_config_file
[ req ]
default_bits = $BITS
prompt = no
default_md = sha256
default_days = $VALIDITY_DAYS
req_extensions = v3_req
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[ req_distinguished_name ]
countryName = US
stateOrProvinceName = California
localityName = SF
0.organizationName = TF
commonName = $cn

[ v3_req ]
basicConstraints = CA:false
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
EOF

in=1
for n in $cn $fqdns ; do
  cat <<EOF >> $openssl_config_file
DNS.$in = $n
EOF
  in=$(( in  + 1 ))
done

in=1
for n in $ips ; do
  cat <<EOF >> $openssl_config_file
IP.$in = $n
EOF
  in=$(( in  + 1 ))
done

cat <<EOF >> $openssl_config_file

[ ca ]
default_ca = CA_default

[ CA_default ]
# Directory and file locations.
dir               = .
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/certs
database          = \$dir/index.txt
serial            = \$dir/serial.txt
RANDFILE          = \$dir/.rand
# For certificate revocation lists.
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
# The root key and root certificate.
private_key       = ca.key.pem
certificate       = ca.crt.pem
# SHA-1 is deprecated, so use SHA-2 instead.
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_optional

[ policy_optional ]
countryName            = optional
stateOrProvinceName    = optional
organizationName       = optional
organizationalUnitName = optional
commonName             = supplied
emailAddress           = optional

[ v3_ca]
# Extensions for a typical CA
# PKIX recommendation.
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer:always
basicConstraints = CA:true

[ crl_ext ]
authorityKeyIdentifier=keyid:always,issuer:always
EOF

  echo "DBG: $openssl_config_file"
  cat $openssl_config_file
}

make_ssl_config "$CN" "$FQDNS" "$IPS"

# create root CA
openssl genrsa -out ca.key.pem $BITS
openssl req -config $openssl_config_file -new -x509 -days $VALIDITY_DAYS -extensions v3_ca -key ca.key.pem -out ca.crt.pem

function print_certs() {
  for i in $@ ; do
    echo
    echo "DBG: $i"
    while read l ; do echo "    $l" ; done < $i
  done
}
print_certs ca.key.pem ca.crt.pem

function cp_result() {
  local src=$1
  local dst_env_name=$2
  [ -n "$dst_env_name" ] || return
  rm -f ${!dst_env_name}
  cp ${src} ${!dst_env_name}
}

cp_result ca.key.pem CA_ROOT_KEY
cp_result ca.crt.pem CA_ROOT_CERT


if [[ -n "$OS_CN" ]] ; then
  make_ssl_config "$OS_CN" "$OS_FQDNS" "$OS_IPS"

  openssl genrsa -out server.key.pem $BITS
  openssl req -config $openssl_config_file -new -key server.key.pem -new -out server.csr.pem
  yes | openssl ca -config $openssl_config_file -extensions v3_req -days 365 -in server.csr.pem -out server.crt.pem
  print_certs server.key.pem server.crt.pem
fi
