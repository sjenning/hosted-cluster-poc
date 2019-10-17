#!/bin/bash

set -eu

source ../config-defaults.sh
source ../lib/common.sh

if [[ -f ./machine-user-data.ign ]]; then
  cat > ../manifests/managed/machine-user-data-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${NAMESPACE}-worker-user-data
  namespace: openshift-machine-api
data:
  disableTemplating: $(echo "false" | base64 | tr -d '\n' | tr -d '\r')
  userData: $(encode ./machine-user-data.ign)
EOF
fi

if [[ -f ./machineset.json ]]; then
  cp ./machineset.json ../manifests/managed/worker-machineset.yaml
fi
