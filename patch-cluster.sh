#!/bin/bash

set -ux

export KUBECONFIG=$(pwd)/pki/admin.kubeconfig

# ingress
oc create secret tls custom-certs-default -n openshift-ingress --cert=pki/ingress-wildcard.pem --key=pki/ingress-wildcard-key.pem
oc patch ingresscontrollers default --type=merge -n openshift-ingress-operator --patch '{"spec":{"defaultCertificate":{"name":"custom-certs-default"}}}'

# image registry
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'