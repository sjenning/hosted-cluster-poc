#!/bin/bash

set -eux

function encode() {
  cat ${1} | base64 | tr -d '\n'
}

cat > ../manifests/managed/kube-controller-manager-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: kube-controller-manager
data:
  kubeconfig: $(encode ../pki/kube-controller-manager.kubeconfig)
  ca.crt: $(encode ../pki/root-ca.pem)
  service-account: $(encode ../pki/service-account-key.pem)
  config.yaml: $(encode config.yaml)
  cluster-signer.crt: $(encode ../pki/cluster-signer.pem)
  cluster-signer.key: $(encode ../pki/cluster-signer-key.pem)
EOF

cp kube-*.yaml ../manifests/managed