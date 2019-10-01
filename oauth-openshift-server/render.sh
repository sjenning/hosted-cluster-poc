#!/bin/bash

set -eux

source ../lib/common.sh

CABUNDLE="$(encode ../pki/root-ca.pem)"

# managed

cat > ../manifests/managed/openshift-apiserver-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: openshift-apiserver
data:
  kubeconfig: $(encode ../pki/service-admin.kubeconfig)
  server.crt: $(encode ../pki/openshift-oauthserver-server.pem)
  server.key: $(encode ../pki/openshift-oauthserver-server-key.pem)
  etcd-client.crt: $(encode ../pki/etcd-client.pem)
  etcd-client.key: $(encode ../pki/etcd-client-key.pem)
  config.yaml: $(encode config.yaml)
  ca.crt: ${CABUNDLE}
EOF

export OPENSHIFT_APISERVER_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image oauth-server)
envsubst < openshift-apiserver-deployment.yaml > ../manifests/managed/openshift-apiserver-deployment.yaml
cp openshift-oauthserver-service.yaml ../manifests/managed

# user

rm -f ../manifests/user/openshift-apiserver-apiservices.yaml

cp openshift-apiserver-user-*.yaml ../manifests/user
