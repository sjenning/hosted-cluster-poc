#!/bin/bash

set -eux

envsubst < machine-approver.deployment.yaml.tmpl > ../manifests/user/machine-approver.deployment.yaml
cp 02-openshift-cluster-machine-approver.rbac.yaml ../manifests/user
cp 01-openshift-cluster-machine-approver.namespace.yaml ../manifests/user/01-openshift-cluster-machine-approver.namespace.yaml
