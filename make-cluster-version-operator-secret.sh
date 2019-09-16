#!/bin/bash

set -eux

function encode() {
  cat ${1} | base64 | tr -d '\n'
}

cat > cluster-version-operator/cluster-version-operator-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: cluster-version-operator
data:
  kubeconfig: $(encode pki/admin.kubeconfig)
EOF
