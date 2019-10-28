#!/bin/bash

set -eu

source ../lib/common.sh
source ../config-defaults.sh

export CA=$(encode ../pki/root-ca.pem)
for secret in etcd-client server peer; do
    if [ "${secret}" == "etcd-client" ]; then
        file="etcd-${CLUSTER_ID}-client"
        pki_path=${secret}
    else
        file="etcd-"${CLUSTER_ID}-${secret}
        pki_path="etcd-"${secret}
    fi

    cat > ../manifests/managed/${file}-tls-secret.yaml <<EOF
kind: Secret
apiVersion: v1
metadata:
  name: ${file}-tls
data:
  ${secret}.crt: $(encode ../pki/${pki_path}.pem)
  ${secret}.key: $(encode ../pki/${pki_path}-key.pem)
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
envsubst < etcd-cluster.yaml > ../manifests/managed/etcd-cluster.yaml
envsubst < etcd-backup-operator.yaml > ../manifests/managed/etcd-backup-operator.yaml
envsubst < etcd-restore-operator.yaml > ../manifests/managed/etcd-restore-operator.yaml
envsubst < etcd-operator.yaml > ../manifests/managed/etcd-operator.yaml
envsubst < etcd-cronjob.yaml > ../manifests/managed/etcd-cronjob.yaml
envsubst < etcd-operator-crd-creation-role-binding.yaml > ../manifests/managed/etcd-operator-crd-creation-role-binding.yaml
envsubst < etcd-operator-psp-cluster-role-binding.yaml > ../manifests/managed/etcd-operator-psp-cluster-role-binding.yaml
