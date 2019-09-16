#!/bin/bash

set -eux

source ./common.sh

cat > kube-scheduler/kube-scheduler-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: kube-scheduler
data:
  kubeconfig: $(encode pki/kube-scheduler.kubeconfig)
  config.yaml: $(encode kube-scheduler/config.yaml)
EOF
