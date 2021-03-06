#!/bin/bash

# Network interface. Run `ip link` if you're not sure.
NETWORK_INTERFACE=eth0

# Right source IP
RIGHTSOURCEIP=10.0.88.0/24

# To use SNAT or not.
# SNAT is faster than MASQUERADE but requires a static IP address.
#=============================
#SNAT=yes
#IP_ADDR=$(ifconfig $NETWORK_INTERFACE | grep -oE 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -oE '([0-9]*\.){3}[0-9]*')
#============ OR =============
SNAT=no
#=============================

# If you have a domain name, put it here, or IP address is being used.
SERVER=$(ifconfig $NETWORK_INTERFACE | grep -oE 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -oE '([0-9]*\.){3}[0-9]*')
#SERVER=example.com

# Certificates.
# Use certificates issued by Let's Encrypt or sign yourself one.
#=============================
#CERT=letsencrypt
#CERT_LE_DIR=/etc/letsencrypt/live/$SERVER
#CERT_CA_COMMON_NAME=$SERVER
#============ OR =============
CERT=self_signed
CERT_CA_COMMON_NAME="strongSwan CA"
#=============================

# Passphrase of client certificate.
# Empty passphrase works on everything except iOS; Cannot click "Next" button.
# You can have more than one client certificate.
PEER_NAME=peer
PEER_FULLNAME="Peer Hunter"
PEER_PASS=hunter2

# Credentials.
# As many users as you wish.
PSK=hunter2
VPN_USERNAME_1=user1
VPN_USERPASS_1=hunter2

# That's all.
#
# Hint: To retrieve ~/foobar.txt from terminal via SSH, run
#     scp username@remotehost:foobar.txt /local/dir
#******************************************************************************

# Install.
apt update
apt upgrade -y
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt install -y strongswan strongswan-pki iptables-persistent libcharon-extra-plugins openssl

# Setup server certificates.
cd ~
# This is the self-signed CA certificate to issue client certificates with.
# If you're using a self-signed certificate, you should e-mail caCert.pem to and trust it on your phone/tablet.
# It's the best practice to import it directly into the strongSwan app on Android.
if [ ! -f caKey.pem ]; then
    ipsec pki --gen --outform pem > caKey.pem
fi
if [ ! -f caCert.pem ]; then
    ipsec pki --self --in caKey.pem --dn "CN=$CERT_CA_COMMON_NAME" --ca --outform pem > caCert.pem
fi
if [ "$CERT" = "self_signed" ]
then
    ipsec pki --gen --outform pem > hostKey.pem
    ipsec pki --pub --in hostKey.pem | ipsec pki --issue --cakey caKey.pem --cacert caCert.pem --dn "CN=$SERVER" --san "$SERVER" --flag serverAuth --flag ikeIntermediate --outform pem > hostCert.pem
    mv hostKey.pem /etc/ipsec.d/private/
    mv hostCert.pem /etc/ipsec.d/certs/
    cp caCert.pem /etc/ipsec.d/cacerts/
elif [ "$CERT" = "letsencrypt" ]
then
    ln -s $CERT_LE_DIR/privkey.pem /etc/ipsec.d/private/hostKey.pem
    ln -s $CERT_LE_DIR/cert.pem /etc/ipsec.d/certs/hostCert.pem
    ln -s $CERT_LE_DIR/chain.pem /etc/ipsec.d/cacerts/caCert.pem
else
    echo "Error: $CERT is not supported."
    exit 1
fi

# Issue client certificate.
if [ ! -f ${PEER_NAME}Key.pem ]; then
    ipsec pki --gen --outform pem > ${PEER_NAME}Key.pem
    ipsec pki --pub --in ${PEER_NAME}Key.pem | ipsec pki --issue --cakey caKey.pem --cacert caCert.pem --dn "CN=$PEER_FULLNAME" --outform pem > ${PEER_NAME}Cert.pem
    # On Windows, use a PKCS#12 file with the CA certificate. Here's how.
    # https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs
    # You can remove the private key if you're using EAP.
    openssl pkcs12 -in ${PEER_NAME}Cert.pem -inkey ${PEER_NAME}Key.pem -certfile caCert.pem -passout pass:$PEER_PASS -export -out ${PEER_NAME}_w_cacert.p12
    # On Android 4.4 and later, you may get a warning ("Network may be monitored by an unknown third party") if the peer.p12 file contains
    # the CA certificate. To avoid that, install this PKCS#12 file without the CA certificate.
    openssl pkcs12 -in ${PEER_NAME}Cert.pem -inkey ${PEER_NAME}Key.pem -passout pass:$PEER_PASS -export -out ${PEER_NAME}_wo_cacert.p12
    mv ${PEER_NAME}Cert.pem /etc/ipsec.d/certs/
fi

# Configure ipsec.conf.
cat <<EOF > /etc/ipsec.conf
config setup
    uniqueids=never 

conn %default
    keyexchange=ikev2
    ike=3des-sha1-modp1024,aes256-sha1-modp1024,3des-sha256-modp1024,aes256-sha256-modp1024,3des-sha384-modp1024,aes256-sha384-modp1024
    auto=add
    dpdaction=clear
    rekey=no
    left=%defaultroute
    leftid=$SERVER
    leftcert=hostCert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightsourceip=$RIGHTSOURCEIP

conn IKEv2_EAP
    eap_identity=%any
    rightauth=eap-mschapv2

conn IKEv2_cert
    leftauth=rsa
    rightauth=rsa
    rightid="CN=*"
    # Separate multiple certificates with commas.
    rightcert=${PEER_NAME}Cert.pem
EOF

# Configure strongswan.conf.
cat <<EOF > /etc/strongswan.conf
charon {
    load_modular = yes
    compress = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
    dns1 = 8.8.8.8
    dns2 = 8.8.4.4
    nbns1 = 8.8.8.8
    nbns2 = 8.8.4.4
}
include strongswan.d/*.conf
EOF

# Configure ipsec.secrets.
cat <<EOF > /etc/ipsec.secrets
: RSA hostKey.pem
: PSK "$PSK"
$VPN_USERNAME_1 %any : EAP "$VPN_USERPASS_1"
EOF

# Setup iptables.
iptables -A INPUT -i $NETWORK_INTERFACE -p esp -j ACCEPT
iptables -A INPUT -i $NETWORK_INTERFACE -p udp --dport 500 -j ACCEPT
iptables -A INPUT -i $NETWORK_INTERFACE -p udp --dport 4500 -j ACCEPT
iptables -t mangle -A FORWARD -o $NETWORK_INTERFACE -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
if [ "$SNAT" = "yes" ]
then
    iptables -t nat -A POSTROUTING -s $RIGHTSOURCEIP -o $NETWORK_INTERFACE -j SNAT --to-source $IP_ADDR
else
    iptables -t nat -A POSTROUTING -s $RIGHTSOURCEIP -o $NETWORK_INTERFACE -j MASQUERADE
fi
netfilter-persistent save

echo "net.ipv4.ip_forward=1" > /etc/sysctl.conf
sysctl -p

systemctl enable strongswan
systemctl restart strongswan
