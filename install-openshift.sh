#!/bin/bash

source config.sh
source lib/common.sh

export API_NODEPORT="${API_NODEPORT:-$EXTERNAL_API_PORT}"

if [ -z "$KUBECONFIG" ]; then
  echo "set KUBECONFIG to user with cluster-admin on the management cluster"
  exit 1
fi

set -eu

# make-pki.sh does not remove the /pki directory and does not regenerate certs that already exist.
# If you wish to regenerate the PKI, remove the /pki directory.
echo "Creating PKI assets"
./make-pki.sh &>/dev/null

echo "Retrieving release pull specs"
export RELEASE_PULLSPECS="$(mktemp)"
fetch_release_pullspecs

echo "Rendering manifests"
rm -rf manifests
mkdir -p manifests/managed manifests/user
KUBEADMIN_PASSWORD=$(openssl rand -hex 24 | tr -d '\n')
echo $KUBEADMIN_PASSWORD > kubeadmin-password
oc create secret generic kubeadmin -n kube-system --from-literal=kubeadmin="$(htpasswd -bnBC 10 "" "${KUBEADMIN_PASSWORD}" | tr -d ':\n')" -oyaml --dry-run > manifests/user/kubeadmin-secret.yaml
oc create secret generic pull-secret --from-file=.dockerconfigjson=pull-secret --type=kubernetes.io/dockerconfigjson -oyaml --dry-run > manifests/managed/pull-secret.yaml
oc create secret generic pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret --type=kubernetes.io/dockerconfigjson -oyaml --dry-run > manifests/user/00-pull-secret.yaml
for component in etcd kube-apiserver kube-controller-manager kube-scheduler cluster-bootstrap openshift-apiserver openshift-controller-manager openvpn cluster-version-operator auto-approver ca-operator user-manifests-bootstrapper; do
  pushd ${component} >/dev/null
  ./render.sh >/dev/null
  popd >/dev/null
done

if [ "${PLATFORM}" != "none" ]; then
  echo "Setting up platform resources"
  ./contrib/${PLATFORM}/setup.sh >/dev/null
fi

echo "Applying management cluster resources"
# use `create ns` instead of `new-project` in case management cluster in not OCP
oc get ns ${NAMESPACE} &>/dev/null || oc create ns ${NAMESPACE} >/dev/null
oc project ${NAMESPACE} >/dev/null
pushd manifests/managed >/dev/null
oc apply -f pull-secret.yaml >/dev/null
oc secrets link default pull-secret --for=pull >/dev/null
rm -f pull-secret.yaml
oc apply -f . >/dev/null
popd >/dev/null

echo "Waiting up to 5m for the Kubernetes API at https://${EXTERNAL_API_DNS_NAME}:${EXTERNAL_API_PORT}"
oc wait --for=condition=Available deployment/kube-apiserver --timeout=5m >/dev/null

echo "Waiting up to 15m for the cluster at https://${EXTERNAL_API_DNS_NAME}:${EXTERNAL_API_PORT} to initialize"
export KUBECONFIG=$(pwd)/pki/admin.kubeconfig
while ! oc wait --for=condition=Available clusterversion/version --timeout=15m &>/dev/null; do
  sleep 10
done

echo "Install complete!"
echo "To access the cluster as the system:admin user when using 'oc', run 'export $(pwd)/pki/admin.kubeconfig"
echo "To join additional nodes to the cluster, use the node-bootstrapper kubeconfig at $(pwd)/pki/kubelet-bootstrap.kubeconfig"
echo "Access the OpenShift web-console here: https://console-openshift-console.${INGRESS_SUBDOMAIN}"
echo "Login into the console with user: kubeadmin, password ${KUBEADMIN_PASSWORD}"
