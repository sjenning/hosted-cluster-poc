#!/bin/bash

set -eu

source ../lib/common.sh

cat > ../manifests/managed/kube-scheduler-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: kube-scheduler
data:
  kubeconfig: $(encode ../pki/kube-scheduler.kubeconfig)
  config.yaml: $(encode config.yaml)
EOF

export HYPERKUBE_IMAGE=$(image_for hyperkube)
envsubst < kube-scheduler-deployment.yaml > ../manifests/managed/kube-scheduler-deployment.yaml
