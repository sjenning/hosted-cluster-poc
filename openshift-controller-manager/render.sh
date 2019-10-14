#!/bin/bash

set -eu

source ../config.sh
source ../lib/common.sh

export DOCKER_BUILDER_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image docker-builder)
export DEPLOYER_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image deployer)
envsubst < config.yaml > config.yaml.rendered

cat > ../manifests/managed/openshift-controller-manager-secret.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: openshift-controller-manager
data:
  kubeconfig: $(encode ../pki/service-admin.kubeconfig)
  server.crt: $(encode ../pki/openshift-controller-manager-server.pem)
  server.key: $(encode ../pki/openshift-controller-manager-server-key.pem)
  ca.crt: $(encode ../pki/root-ca.pem)
  config.yaml: $(encode config.yaml.rendered)
EOF

rm -f config.yaml.rendered

export OPENSHIFT_CONTROLLER_MANAGER_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image openshift-controller-manager)
envsubst < openshift-controller-manager-deployment.yaml > ../manifests/managed/openshift-controller-manager-deployment.yaml

cp openshift-controller-manager-namespace.yaml ../manifests/user/00-openshift-controller-manager-namespace.yaml
cat > ../manifests/user/openshift-controller-manager-service-ca.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
  name: openshift-service-ca
  namespace: openshift-controller-manager
data: {}
EOF
