#!/bin/bash

set -ux

export KUBECONFIG=$(pwd)/pki/admin.kubeconfig

# ingress
oc create secret tls custom-certs-default -n openshift-ingress --cert=pki/ingress-wildcard.pem --key=pki/ingress-wildcard-key.pem
oc patch ingresscontrollers default --type=merge -n openshift-ingress-operator --patch '{"spec":{"defaultCertificate":{"name":"custom-certs-default"}}}'

# create admin demo user with password "demo"
oc create secret generic htpass-secret --from-literal=htpasswd=$(htpasswd -bnBC 10 demo demo | tr -d '\n') -n openshift-config
cat << EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: demo_htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF
oc adm policy add-cluster-role-to-user cluster-admin demo
