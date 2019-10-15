#!/bin/bash

set -eu

source ../config.sh
source ../lib/common.sh

# server
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
  server.conf: $(encode server.conf)
EOF
cat > ../manifests/managed/openvpn-ccd-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: openvpn-ccd
data:
  worker: $(encode worker)
EOF
cp openvpn-server-deployment.yaml ../manifests/managed/openvpn-server-deployment.yaml
envsubst < openvpn-server-service.yaml > ../manifests/managed/openvpn-server-service.yaml

# client
envsubst < client.conf > client.conf.rendered
cat > ../manifests/user/openvpn-client-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: openvpn-client
  namespace: kube-system
data:
  tls.crt: $(encode ../pki/openvpn-worker-client.pem)
  tls.key: $(encode ../pki/openvpn-worker-client-key.pem)
  ca.crt: $(encode ../pki/openvpn-ca.pem)
  client.conf: $(encode client.conf.rendered)
EOF
rm -f client.conf.rendered
cp openvpn-client-deployment.yaml ../manifests/user/openvpn-client-deployment.yaml
