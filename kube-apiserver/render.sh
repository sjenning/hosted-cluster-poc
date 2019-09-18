#!/bin/bash

set -eux

source ../lib/common.sh

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
  ca.crt: $(encode ../pki/root-ca.pem)
  service-account.pub: $(encode ../pki/service-account.pem)
  config.yaml: $(encode config.yaml)
EOF

export HYPERKUBE_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image hyperkube)
envsubst < kube-apiserver-deployment.yaml > ../manifests/managed/kube-apiserver-deployment.yaml
cp kube-apiserver-service.yaml ../manifests/managed
