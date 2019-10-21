#!/bin/bash

set -eu

source ../config-defaults.sh
source ../lib/common.sh

cat > ../manifests/managed/kube-controller-manager-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: kube-controller-manager
data:
  kubeconfig: $(encode ../pki/kube-controller-manager.kubeconfig)
  ca.crt: $(encode ../pki/combined-ca.pem)
  service-account: $(encode ../pki/service-account-key.pem)
  config.yaml: $(cat config.yaml | envsubst | encode -)
  cluster-signer.crt: $(encode ../pki/cluster-signer.pem)
  cluster-signer.key: $(encode ../pki/cluster-signer-key.pem)
EOF

export HYPERKUBE_IMAGE=$(image_for hyperkube)
if [[ "$DEPLOY_HA" == "true" ]]; then
  envsubst < kube-controller-manager-ha-deployment.yaml > ../manifests/managed/kube-controller-manager-deployment.yaml
else
  envsubst < kube-controller-manager-deployment.yaml > ../manifests/managed/kube-controller-manager-deployment.yaml
fi
envsubst < kube-controller-manager-deployment.yaml > ../manifests/managed/kube-controller-manager-deployment.yaml
