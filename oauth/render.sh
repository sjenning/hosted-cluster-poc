#!/bin/bash

set -eu

source ../config-defaults.sh
source ../lib/common.sh

echo -ne "$OAUTH_CLIENT_SECRET" > ../pki/oauthclientsecret
cat > ../manifests/user/oauth-client-secret.yml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: openshift-apiserver
data:
  clientSecret: $(encode ../pki/oauthclientsecret)
EOF

envsubst < openshift-apiserver-deployment.yaml > ../manifests/managed/openshift-apiserver-deployment.yaml
envsubst < oauth-crd.yaml > ../manifests/user/oauth-crd.yaml

