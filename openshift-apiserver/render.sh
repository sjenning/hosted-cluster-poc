#!/bin/bash

set -eux

function encode() {
  cat ${1} | base64 | tr -d '\n'
}

CABUNDLE="$(encode ../pki/root-ca.pem)"

# managed assets

cat > ../manifests/managed/openshift-apiserver-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: openshift-apiserver
data:
  kubeconfig: $(encode ../pki/admin.kubeconfig)
  server.crt: $(encode ../pki/openshift-apiserver-server.pem)
  server.key: $(encode ../pki/openshift-apiserver-server-key.pem)
  etcd-client.crt: $(encode ../pki/etcd-client.pem)
  etcd-client.key: $(encode ../pki/etcd-client-key.pem)
  config.yaml: $(encode config.yaml)
  ca.crt: ${CABUNDLE}
EOF

cp openshift-apiserver-deployment.yaml ../manifests/managed
cp openshift-apiserver-service.yaml ../manifests/managed

# user assets

for apiservice in v1.apps.openshift.io v1.authorization.openshift.io v1.build.openshift.io v1.image.openshift.io v1.oauth.openshift.io v1.project.openshift.io v1.quota.openshift.io v1.route.openshift.io v1.security.openshift.io v1.template.openshift.io v1.user.openshift.io; do
cat >> ../manifests/user/openshift-apiserver-apiservices.yaml <<EOF 
---
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: ${apiservice}
spec:
  caBundle: ${CABUNDLE}
  group: ${apiservice#*.}
  groupPriorityMinimum: 9900
  service:
    name: openshift-apiserver
    namespace: default
  version: v1
  versionPriority: 15
EOF
done

cp openshift-apiserver-user-service.yaml ../manifests/user