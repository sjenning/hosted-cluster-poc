#!/bin/bash

set -eux

source ../lib/common.sh

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

export HYPERKUBE_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image hyperkube)
envsubst < kube-controller-manager-deployment.yaml > ../manifests/managed/kube-controller-manager-deployment.yaml

cp openshift-infra-namespace.yaml ../manifests/user
