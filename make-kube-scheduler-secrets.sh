#!/bin/bash

set -eux

function encode() {
  cat ${1} | base64 | tr -d '\n'
}

cat > kube-scheduler/kube-scheduler-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: kube-scheduler
data:
  kubeconfig: $(encode pki/kube-scheduler.kubeconfig)
  config.yaml: $(encode kube-scheduler/config.yaml)
EOF