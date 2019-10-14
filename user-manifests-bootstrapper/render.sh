#!/bin/bash

set -eu

source ../config.sh
source ../lib/common.sh

for f in ../manifests/user/{*.yaml,*.yml}; do
  IFS=’.’ read -ra NAME <<< "$(basename "${f}")"
  cmname=$(echo ${NAME[0]} | tr '_' '-')
  oc create configmap user-manifest-${cmname} --from-file=data=$f --dry-run -o yaml > ../manifests/managed/user_manifest_$(basename $f)
done

cat > ../manifests/managed/kube-service-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kube-service-kubeconfig
data:
  kubeconfig: $(encode ../pki/service-admin.kubeconfig)
EOF

export CLI_IMAGE=$(image_for cli)
envsubst '$CLI_IMAGE' < user-manifests-bootstrapper.yaml > ../manifests/managed/user-manifests-bootstrapper-pod.yaml
