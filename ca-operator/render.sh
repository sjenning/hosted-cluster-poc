#!/bin/bash

set -eu

source ../config.sh
source ../lib/common.sh

cat > ../manifests/managed/ca-operator-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: ca-operator-secret
data:
  ca.crt: $(encode ../pki/combined-ca.pem)
  kubeconfig: $(encode ../pki/admin.kubeconfig)
EOF

export CLI_IMAGE=$(image_for cli)
envsubst '$CLI_IMAGE' < ca-operator-deployment.yaml > ../manifests/managed/ca-operator-deployment.yaml
