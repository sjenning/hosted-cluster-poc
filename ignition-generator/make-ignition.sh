#!/bin/bash

set -eux

echo "copying PKI assets"
rm -rf fake-root/var/lib/kubernetes
mkdir -p fake-root/var/lib/kubernetes
cp ../pki/kubelet-bootstrap.kubeconfig ../pki/kube-proxy.kubeconfig ../pki/root-ca.pem fake-root/var/lib/kubernetes
echo "transpiling files"
./filetranspile -i base.ign -f fake-root -o tmp.ign
echo "transpiling units"
./unittranspile -i tmp.ign -u units -o final.ign
rm -f tmp.ign
echo "Ignition file is ready in final.ign"
