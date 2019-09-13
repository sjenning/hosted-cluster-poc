#!/bin/bash

set -eux

function encode() {
  cat ${1} | base64 | tr -d '\n'
}

cat > kube-controller-manager/kube-controller-manager-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: kube-controller-manager
data:
  kubeconfig: $(encode pki/kube-controller-manager.kubeconfig)
  ca.crt: $(encode pki/ca.pem)
  service-account: $(encode pki/service-account-key.pem)
EOF