#!/bin/bash

source config.sh

if [ -z "$KUBECONFIG" ]; then
  echo "set KUBECONFIG to user with cluster-admin on the management cluster"
  exit 1
fi

set -eu

if [ "${PLATFORM}" != "none" ]; then
  echo "Tearing down platform resources"
  if [[ -f ./contrib/${PLATFORM}/teardown.sh ]]; then
    ./contrib/${PLATFORM}/teardown.sh >/dev/null
  fi
fi

echo "Deleting management cluster resources"
oc get ns ${NAMESPACE} &>/dev/null && oc delete ns ${NAMESPACE} >/dev/null

echo "Uninstall complete!"
