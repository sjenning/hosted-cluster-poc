#!/bin/bash

set -eux

source config.sh

# make-pki.sh does not remove the /pki directory and does not regenerate certs that already exist.
# If you wish to regenerate the PKI, remove the /pki directory.
./make-pki.sh

rm -rf manifests
mkdir -p manifests/managed manifests/user

if [ ! -e pull-secret ]; then
  echo "please provide a pull-secret file"
  exit 1
fi
oc create secret generic pull-secret --from-file=.dockerconfigjson=pull-secret --type=kubernetes.io/dockerconfigjson -oyaml --dry-run > manifests/managed/00-pull-secret.yaml
oc create secret generic pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret --type=kubernetes.io/dockerconfigjson -oyaml --dry-run > manifests/user/00-pull-secret.yaml

for component in etcd kube-apiserver kube-controller-manager kube-scheduler cluster-bootstrap openshift-apiserver openshift-controller-manager cluster-version-operator auto-approver user-manifests-bootstrapper; do
  pushd ${component}
  ./render.sh
  popd
done
