#!/bin/bash

set -eo pipefail

echo ""
echo "                                           __                       ___  __                           ";
echo "                            .-----..-----.|__|.----..-----..-----..'  _||  |_                         ";
echo "                            |  -__||  _  ||  ||  __||__ --||  _  ||   _||   _|                        ";
echo "                            |_____||   __||__||____||_____||_____||__|  |____|                        ";
echo "                                   |__|                                                               ";
echo " _______                         __    __                   __        ______         __               ";
echo "|     __|.--------..---.-..----.|  |_ |  |--..-----..-----.|  |_     |   __ \.-----.|  |.---.-..--.--.";
echo "|__     ||        ||  _  ||   _||   _||     ||  _  ||__ --||   _|    |      <|  -__||  ||  _  ||  |  |";
echo "|_______||__|__|__||___._||__|  |____||__|__||_____||_____||____|    |___|__||_____||__||___._||___  |";
echo "                                                                                               |_____|";
echo ""

echo "First the set variables are checked"

#### Validation of environments
if [ -z "${SMARTHOST_HOST}" ]; then
  echo "You need to set the 'SMARTHOST_HOST' environment variable."
  exit 101
fi
if [ -z "${SMARTHOST_PORT}" ]; then
  echo "You need to set the 'SMARTHOST_PORT' environment variable."
  exit 102
fi
if [ -z "${SMARTHOST_USER}" ]; then
  echo "You need to set the 'SMARTHOST_USER' environment variable."
  exit 103
fi
if [ -z "${SMARTHOST_PASSWORD}" ]; then
  echo "You need to set the 'SMARTHOST_PASSWORD' environment variable."
  exit 104
fi
if [ -z "${SMARTHOST_USE_TLS}" ]; then
  echo "You need to set the 'SMARTHOST_USE_TLS' environment variable."
  exit 105
fi
if [ -z "${SMARTHOST_NETWORKS}" ]; then
  echo "You need to set the 'SMARTHOST_NETWORKS' environment variable."
  exit 106
fi
if [ -z "${SMARTHOST_DOMAIN}" ]; then
  echo "You need to set the 'SMARTHOST_DOMAIN' environment variable."
  exit 107
fi
if [ -z "${SMARTHOST_ADD_MISSING_HEADERS}" ]; then
  echo "You need to set the 'SMARTHOST_ADD_MISSING_HEADERS' environment variable."
  exit 108
fi

echo "Set variables successfully checked"
echo "Configuration is performed"

#### Defaults
postconf -e maillog_file=/dev/stdout
postconf -e inet_interfaces=all
postconf -e inet_protocols=ipv4
postconf -e smtp_host_lookup=native,dns
postconf -e smtp_sasl_auth_enable=yes
postconf -e smtp_sasl_password_maps=lmdb:/etc/postfix/sasl_passwd
postconf -e smtp_sasl_security_options=noanonymous
postconf -e mydomain=${SMARTHOST_DOMAIN}
postconf -e myhostname=mail.${SMARTHOST_DOMAIN}
postconf -e myorigin=${SMARTHOST_DOMAIN}
postconf -e mydestination=localhost
postconf -e mynetworks=${SMARTHOST_NETWORKS}

if [ ! -z "$(echo ${SMARTHOST_ADD_MISSING_HEADERS} | grep -i -E "(yes|true|1)")" ]; then
  postconf -e always_add_missing_headers=yes
else
  postconf -e always_add_missing_headers=no
fi

#### Host / Port / User / Pass
postconf -e relayhost="[${SMARTHOST_HOST}]:${SMARTHOST_PORT}";
echo "[${SMARTHOST_HOST}]:${SMARTHOST_PORT} ${SMARTHOST_USER}:${SMARTHOST_PASSWORD}" > /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

#### TLS
if [ ! -z "$(echo ${SMARTHOST_USE_TLS} | grep -i -E "(yes|true|1)")" ]; then
  postconf -e smtp_use_tls=yes
fi

#### Port 465
if [ "${SMARTHOST_PORT}" == "465" ]; then
  postconf -e smtp_tls_wrappermode=yes
  postconf -e smtp_tls_security_level=encrypt
fi

#### Replace from address
if [ ! -z "${SMARTHOST_FORCE_FROM}" ]; then
  echo "/^From:.*$/ REPLACE From: ${SMARTHOST_FORCE_FROM}" > /etc/postfix/header_check
  postconf -e smtp_header_checks=regexp:/etc/postfix/header_check
  postmap /etc/postfix/header_check
fi

echo "Configuration success"
echo "Starting Smarthost"

exec postfix -c /etc/postfix start-fg
