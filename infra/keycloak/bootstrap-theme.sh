#!/bin/sh
set -eu

for i in $(seq 1 60); do
  if /opt/keycloak/bin/kcadm.sh config credentials --server http://keycloak:8080/auth --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if /opt/keycloak/bin/kcadm.sh get realms/forestmap >/dev/null 2>&1; then
  /opt/keycloak/bin/kcadm.sh update realms/forestmap -s loginTheme=forestmap -s accountTheme=keycloak.v3 -s emailTheme=keycloak -s adminTheme=keycloak.v3
fi
