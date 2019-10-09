#!/bin/bash

# THIS IS A HACK
# until we get the vpn bits integrated
# assumes:
# there is only one node in the management cluster (only sets routes on the node on which the pod is scheduled)
# the nodes for the management and user clusters are on the same subnet

set -eu

source ../config.sh

if [ "${PLATFORM}" != "openstack" ]; then
  exit 0
fi

source ../lib/common.sh

cat > ../manifests/managed/kube-external-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kube-external-kubeconfig
data:
  kubeconfig: $(encode ../pki/admin.kubeconfig)
EOF

export CLI_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image cli)
export NODE_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image node)
envsubst '${CLI_IMAGE} ${NODE_IMAGE}' < route-setter.yaml > ../manifests/managed/route-setter.yaml