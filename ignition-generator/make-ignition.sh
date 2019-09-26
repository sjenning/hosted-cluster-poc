#!/bin/bash

set -eux

echo "copying PKI assets"
cp ../pki/kubelet-bootstrap.kubeconfig fake-root/etc/kubernetes/kubeconfig
# kubeconfig needs to be world readable because network-operator reads it for server URL
chmod +r fake-root/etc/kubernetes/kubeconfig
cp ../pki/root-ca.pem fake-root/etc/kubernetes/ca.crt
echo "transpiling files"
./filetranspile -i base.ign -f fake-root -o tmp.ign
echo "transpiling units"
./unittranspile -i tmp.ign -u units -o final.ign
rm -f tmp.ign
echo "Ignition file is ready in final.ign"

echo "Generating machineconfig"
export WORKER_IGNITION_JSON=$(cat final.ign)
envsubst < worker-remote.machineconfig.yaml.tmpl > ./worker-remote.machineconfig.yaml

echo "Generating machine user-data"
export BOOTSTRAP_USER_DATA=$(cat bootstrap-final.ign | base64 -w0)
envsubst < ./worker-remote-user-data.secret.yaml.tmpl > ./worker-remote-user-data.secret.yaml
