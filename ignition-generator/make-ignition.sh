#!/bin/bash

set -eu

echo "copying PKI assets"
cp ../pki/kubelet-bootstrap.kubeconfig fake-root/etc/kubernetes/kubeconfig
# kubeconfig needs to be world readable because network-operator reads it for server URL
chmod +r fake-root/etc/kubernetes/kubeconfig
cp ../pki/root-ca.pem fake-root/etc/kubernetes/ca.crt
echo "copy pull secret"
mkdir -p fake-root/var/lib/kubelet
cp ../pull-secret fake-root/var/lib/kubelet/config.json
echo "transpiling files"
./filetranspile -i base.ign -f fake-root -o tmp.ign
echo "transpiling units"
./unittranspile -i tmp.ign -u units -o final.ign
rm -f tmp.ign
echo "Ignition file is ready in final.ign"
