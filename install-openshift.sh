#!/bin/bash

set -x

source config.sh

export API_NODEPORT="${API_NODEPORT:-$EXTERNAL_API_PORT}"

if [ -z "$KUBECONFIG" ]; then
  echo "set KUBECONFIG to user with cluster-admin on the management cluster"
  exit 1
fi

if oc get ns ${NAMESPACE}; then
  echo "namespace '${NAMESPACE}' already exists in the management cluster"
  exit 1
fi

set -eu

# make-pki.sh does not remove the /pki directory and does not regenerate certs that already exist.
# If you wish to regenerate the PKI, remove the /pki directory.
echo "Rendering PKI"
./make-pki.sh

echo "Rendering manifests"
rm -rf manifests
mkdir -p manifests/managed manifests/user
touch pull-secret
oc create secret generic pull-secret --from-file=.dockerconfigjson=pull-secret --type=kubernetes.io/dockerconfigjson -oyaml --dry-run > manifests/managed/pull-secret.yaml
oc create secret generic pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret --type=kubernetes.io/dockerconfigjson -oyaml --dry-run > manifests/user/00-pull-secret.yaml
for component in etcd kube-apiserver kube-controller-manager kube-scheduler cluster-bootstrap openshift-apiserver openshift-controller-manager cluster-version-operator auto-approver machine-api ca-operator user-manifests-bootstrapper; do
  pushd ${component}
  ./render.sh
  popd
done

if [ "${PLATFORM}" != "none" ]; then
  echo "Creating platform resources"
  ./contrib/${PLATFORM}/setup.sh
fi

echo "Creating cluster"
# use `create ns` instead of `new-project` in case management cluster in not OCP
oc create ns ${NAMESPACE}
oc project ${NAMESPACE}
cd manifests/managed
oc apply -f pull-secret.yaml
oc secrets link default pull-secret --for=pull
rm -f pull-secret.yaml
oc apply -f .

echo "Waiting for API to be healthy..."
oc wait --for=condition=Available deployment/kube-apiserver --timeout=5m
oc wait --for=condition=Available deployment/openshift-apiserver --timeout=5m

echo "Installation complete! The cluster is now ready for nodes to be added."
echo "cluster-admin kubeconfig for cluster administration is at pki/admin.kubeconfig"
echo "node-bootstrapper kubeconfig for joining nodes to the cluster is at pki/kubelet-bootstrap.kubeconfig "
echo "Once nodes are added to the cluster, the remaining OpenShift components will deploy."
