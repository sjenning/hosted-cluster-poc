#!/bin/bash

source config.sh

export API_NODEPORT="${API_NODEPORT:-$EXTERNAL_API_PORT}"

if [ -z "$KUBECONFIG" ]; then
  echo "set KUBECONFIG to user with cluster-admin on the management cluster"
  exit 1
fi

if ! oc get ns ${NAMESPACE} &>/dev/null; then
  echo "namespace '${NAMESPACE}' not found in the management cluster"
  exit 1
fi

set -eu

echo "Pulling release image"
touch pull-secret
REGISTRY_AUTH_FILE=$(pwd)/pull-secret ${CONTAINER_CLI} pull ${RELEASE_IMAGE} >/dev/null

echo "Rendering manifests"
rm -rf manifests
mkdir -p manifests/managed manifests/user
for component in etcd kube-apiserver kube-controller-manager kube-scheduler openshift-apiserver openshift-controller-manager cluster-version-operator auto-approver ca-operator; do
  pushd ${component} >/dev/null
  ./render.sh >/dev/null
  popd >/dev/null
done

echo "Applying management cluster resources"
oc project ${NAMESPACE} >/dev/null
pushd manifests/managed >/dev/null
# don't update KCM secret as the ca-operator updates it with the service and ingress CAs
rm -f kube-controller-manager-secret.yaml
oc apply -f . >/dev/null
popd >/dev/null

echo "Running oc adm upgrade"
export KUBECONFIG=$(pwd)/pki/admin.kubeconfig
while ! oc adm upgrade --force --to-image="${RELEASE_IMAGE}"; do
  sleep 10
done

echo "Upgrade is in progress."
echo "Run 'oc get clusterversion' to monitor upgrade status."
