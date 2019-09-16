#!/bin/bash

set -eux

envsubst < template/etcd-operator-cluster-role-binding.yaml > etcd/operator-cluster-role-binding.yaml
