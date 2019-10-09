#!/bin/bash

set -eu

source ../lib/common.sh

cat > ../manifests/managed/cluster-version-operator-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: cluster-version-operator
data:
  kubeconfig: $(encode ../pki/service-admin.kubeconfig)
EOF

envsubst < cluster-version-operator-deployment.yaml > ../manifests/managed/cluster-version-operator-deployment.yaml
cp cluster-version-namespace.yaml ../manifests/user
