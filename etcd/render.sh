#!/bin/bash

set -eu

source ../lib/common.sh
source ../config.sh

export CA=$(encode ../pki/root-ca.pem)
for secret in etcd-client server peer; do
    if [ "${secret}" == "etcd-client" ]; then
        file="etcd-${CLUSTER_ID}-client"
    else
        file="etcd-"${CLUSTER_ID}-${secret}
    fi

    cat > ../manifests/managed/${file}-tls-secret.yaml <<EOF
kind: Secret
apiVersion: v1
metadata:
  name: ${file}-tls
data:
  ${secret}.crt: $(encode ../pki/${secret}.pem)
  ${secret}.key: $(encode ../pki/${secret}-key.pem)
  ${secret}-ca.crt: ${CA}
EOF
done

envsubst < config_temp.txt > config.txt
envsubst < credentials_temp.txt > credentials.txt

cat > ../manifests/managed/cos-credentials.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cos-credentials
type: Opaque
data:
  config: $(encode config.txt)
  credentials: $(encode credentials.txt)
EOF

cp *.yaml ../manifests/managed
envsubst < etcd-operator-cluster-role-binding.yaml > ../manifests/managed/etcd-operator-cluster-role-binding.yaml
envsubst < etcd-cluster.yaml > ../manifests/managed/etcd-cluster.yaml
envsubst < etcd-cronjob.yaml > ../manifests/managed/etcd-cronjob.yaml
envsubst < etcd-nodeport-service.yaml > ../manifests/managed/etcd-nodeport-service.yaml
