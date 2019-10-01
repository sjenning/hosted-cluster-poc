#!/bin/bash

# pass in path to oc command as first arg.
$1 create secret generic remote-worker-ignition --from-file=./final.ign -n openshift-machine-config-operator
