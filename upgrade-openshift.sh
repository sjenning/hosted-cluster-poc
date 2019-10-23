#!/bin/bash

source config-defaults.sh
source lib/common.sh

export API_NODEPORT="${API_NODEPORT:-$EXTERNAL_API_PORT}"

if [ -z "$KUBECONFIG" ]; then
  echo "set KUBECONFIG to user with cluster-admin on the management cluster"
  exit 1
fi

if ! oc project ${NAMESPACE} &>/dev/null; then
  echo "namespace '${NAMESPACE}' not found in the management cluster"
  exit 1
fi

set -eu

echo "Retrieving release pull specs"
export RELEASE_PULLSPECS="$(mktemp)"
fetch_release_pullspecs

echo "Rendering manifests"
rm -rf manifests
mkdir -p manifests/managed manifests/user
for component in etcd kube-apiserver kube-controller-manager kube-scheduler openshift-apiserver openshift-controller-manager cluster-version-operator auto-approver ca-operator; do
  pushd ${component} >/dev/null
  ./render.sh >/dev/null
  popd >/dev/null
done

echo "Scaling down management cluster CVO"
oc scale deployment cluster-version-operator --replicas=0 --timeout=1m

MGMT_KUBECONFIG="$KUBECONFIG"
export KUBECONFIG=$(pwd)/pki/admin.kubeconfig

### BEGIN USER CLUSTER OPERATIONS ###

# Its possible that the user cluster components may not always exist
if oc get deployment -n openshift-cluster-version cluster-version-operator &>/dev/null; then
  echo "TEMPORARY: Removing user cluster CVO"
  oc delete deployment -n openshift-cluster-version cluster-version-operator
fi

echo "Running oc adm upgrade"
oc adm upgrade --force --to-image="${RELEASE_IMAGE}"

### BEGIN USER CLUSTER OPERATIONS ###

export KUBECONFIG="$MGMT_KUBECONFIG"

echo "Applying management cluster resources"
oc project ${NAMESPACE} >/dev/null
pushd manifests/managed >/dev/null
# don't update KCM secret as the ca-operator updates it with the service and ingress CAs
rm -f kube-controller-manager-secret.yaml
oc apply -f . >/dev/null
popd >/dev/null

echo "Upgrade is in progress."
echo "Run 'oc get clusterversion' on the user cluster to monitor upgrade status."
