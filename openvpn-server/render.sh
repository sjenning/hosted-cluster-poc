#!/bin/bash

set -eu

source ../config.sh
source ../lib/common.sh

cat > ../manifests/managed/openvpn-server-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: openvpn-server
data:
  tls.crt: $(encode ../pki/openvpn-server.pem)
  tls.key: $(encode ../pki/openvpn-server-key.pem)
  ca.crt: $(encode ../pki/openvpn-ca.pem)
  dh.pem: $(encode ../pki/openvpn-dh.pem)
  kubernetes.conf: $(encode kubernetes.conf)
EOF

cp openvpn-server-deployment.yaml ../manifests/managed/openvpn-server-deployment.yaml
envsubst < openvpn-server-service.yaml > ../manifests/managed/openvpn-server-service.yaml
