#!/bin/bash

set -eux

function encode() {
    cat ${1} | base64 | tr -d '\n'
}

export CA=$(encode pki/ca.pem)
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
  ${secret}.crt: $(encode pki/${file}.pem)
  ${secret}.key: $(encode pki/${file}-key.pem)
  ${secret}-ca.crt: ${CA}
EOF
done

cp *.yaml ../manifests/managed
