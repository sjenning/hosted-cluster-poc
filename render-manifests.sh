#!/bin/bash

set -eux

RELEASE_IMAGE=$(curl -s "https://origin-release.svc.ci.openshift.org/api/v1/releasestream/4.2.0-0.okd/latest" | jq -r .pullSpec)

source config.sh

# make-pki.sh does not remove the /pki directory and does not regenerate certs that already exist.
# If you wish to regenerate the PKI, remove the /pki directory.
./make-pki.sh

rm -rf manifests
mkdir -p manifests/managed manifests/user

for component in etcd kube-apiserver kube-controller-manager kube-scheduler openshift-apiserver; do
    pushd ${component}
    ./render.sh "${RELEASE_IMAGE}"
    popd
done
