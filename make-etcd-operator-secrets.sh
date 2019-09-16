#!/bin/bash

set -eux

function encode() {
    cat ${1} | base64 | tr -d '\n'
}

export CA=$(encode pki/ca.pem)
for secret in etcd-client server peer; do
    export SECRET=${secret}
    FILE=${SECRET}
    if [ "${FILE}" != "etcd-client" ]; then
        FILE="etcd-${SECRET}"
    fi
    export FILE
    
    export CRT=$(encode pki/${FILE}.pem)
    export KEY=$(encode pki/${FILE}-key.pem)
    envsubst < template/etcd-secret-template.yaml > etcd/${FILE}-tls-secret.yaml
done
