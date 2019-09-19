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
