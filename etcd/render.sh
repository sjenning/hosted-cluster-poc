#!/bin/bash

set -eux

source ../lib/common.sh
source ../config.sh

export CA=$(encode ../pki/root-ca.pem)
for secret in etcd-client server peer; do
    file=${secret}
    if [ "${file}" != "etcd-client" ]; then
        file="etcd-${secret}"
    fi

    cat > ../manifests/managed/${file}-tls-secret.yaml <<EOF
kind: Secret
apiVersion: v1
metadata:
  name: ${file}-tls
data:
  ${secret}.crt: $(encode ../pki/${file}.pem)
  ${secret}.key: $(encode ../pki/${file}-key.pem)
  ${secret}-ca.crt: ${CA}
EOF
done

cp *.yaml ../manifests/managed
envsubst < etcd-operator-cluster-role-binding.yaml > ../manifests/managed/etcd-operator-cluster-role-binding.yaml