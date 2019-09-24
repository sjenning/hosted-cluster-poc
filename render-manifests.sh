#!/bin/bash

set -eux

source config.sh

# make-pki.sh does not remove the /pki directory and does not regenerate certs that already exist.
# If you wish to regenerate the PKI, remove the /pki directory.
./make-pki.sh

rm -rf manifests
mkdir -p manifests/managed manifests/user

for component in etcd kube-apiserver kube-controller-manager kube-scheduler cluster-bootstrap openshift-apiserver openshift-controller-manager cluster-version-operator user-manifests-bootstrapper; do
    pushd ${component}
    ./render.sh
    popd
done
