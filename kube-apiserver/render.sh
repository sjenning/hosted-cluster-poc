#!/bin/bash

set -eu

source ../config.sh
source ../lib/common.sh

export OAUTH_ROUTE="oauth-openshift.${INGRESS_SUBDOMAIN}"

cat > oauthMetadata.json <<EOF
{
  "issuer": "https://${OAUTH_ROUTE}",
  "authorization_endpoint": "https://${OAUTH_ROUTE}/oauth/authorize",
  "token_endpoint": "https://${OAUTH_ROUTE}/oauth/token",
  "scopes_supported": [
    "user:check-access",
    "user:full",
    "user:info",
    "user:list-projects",
    "user:list-scoped-projects"
  ],
  "response_types_supported": [
    "code",
    "token"
  ],
  "grant_types_supported": [
    "authorization_code",
    "implicit"
  ],
  "code_challenge_methods_supported": [
    "plain",
    "S256"
  ]
}
EOF

envsubst < config.yaml > config.yaml.rendered
cat > ../manifests/managed/kube-apiserver-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: kube-apiserver
data:
  server.crt: $(encode ../pki/kube-apiserver-server.pem)
  server.key: $(encode ../pki/kube-apiserver-server-key.pem)
  kubelet-client.crt: $(encode ../pki/kube-apiserver-kubelet.pem)
  kubelet-client.key: $(encode ../pki/kube-apiserver-kubelet-key.pem)
  etcd-client.crt: $(encode ../pki/etcd-client.pem)
  etcd-client.key: $(encode ../pki/etcd-client-key.pem)
  proxy-client.crt: $(encode ../pki/kube-apiserver-aggregator-proxy-client.pem)
  proxy-client.key: $(encode ../pki/kube-apiserver-aggregator-proxy-client-key.pem)
  ca.crt: $(encode ../pki/combined-ca.pem)
  service-account.pub: $(encode ../pki/service-account.pem)
  config.yaml: $(encode config.yaml.rendered)
  oauthMetadata: $(encode oauthMetadata.json)
EOF
rm -f config.yaml.rendered oauthMetadata.json

envsubst < client.conf > client.conf.rendered
cat > ../manifests/managed/openvpn-client-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: openvpn-client
data:
  tls.crt: $(encode ../pki/openvpn-client.pem)
  tls.key: $(encode ../pki/openvpn-client-key.pem)
  ca.crt: $(encode ../pki/openvpn-ca.pem)
  client.conf: $(encode client.conf.rendered)
EOF
rm -f client.conf.rendered

export HYPERKUBE_IMAGE=$(image_for hyperkube)
envsubst < kube-apiserver-deployment.yaml > ../manifests/managed/kube-apiserver-deployment.yaml
envsubst < kube-apiserver-service.yaml > ../manifests/managed/kube-apiserver-service.yaml
