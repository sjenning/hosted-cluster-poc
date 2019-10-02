#!/bin/bash

set -eux

source ../lib/common.sh

CABUNDLE="$(encode ../pki/root-ca.pem)"

# managed

cat > ../manifests/managed/openshift-oauthserver-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: openshift-oauthserver
data:
  kubeconfig: $(encode ../pki/service-admin.kubeconfig)
  server.crt: $(encode ../pki/oauth-openshift.pem)
  server.key: $(encode ../pki/oauth-openshift-key.pem)
  etcd-client.crt: $(encode ../pki/etcd-client.pem)
  etcd-client.key: $(encode ../pki/etcd-client-key.pem)
  config.yaml: $(encode config.yaml)
  ca.crt: ${CABUNDLE}
EOF

export OPENSHIFT_OAUTHSERVER_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image oauth-server)
envsubst < openshift-oauthserver-deployment.yaml > ../manifests/managed/openshift-oauthserver-deployment.yaml
cp openshift-oauthserver-service.yaml ../manifests/managed

# user

envsubst < openshift-oauth-client.yaml > ../manifests/user/openshift-oauth-client.yaml
cp openshift-oauthserver-user-*.yaml ../manifests/user
cp v4-*.yaml ../manifests/managed
