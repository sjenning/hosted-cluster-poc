#!/bin/bash

set -eux

source ../config.sh

cp *.yaml *.yml ../manifests/user

for i in *-config.yml; do
  envsubst < $i > ../manifests/user/$i
done

oc create configmap kubelet-serving-ca --dry-run -oyaml -n openshift-config-managed --from-file=ca-bundle.crt=../pki/cluster-signer.pem > ../manifests/user/kubelet-serving-ca-configmap.yaml