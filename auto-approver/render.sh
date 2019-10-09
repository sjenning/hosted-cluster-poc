#!/bin/bash

set -eu

export CLI_IMAGE=$(${CONTAINER_CLI} run -ti --rm ${RELEASE_IMAGE} image cli)
envsubst '$CLI_IMAGE' < auto-approver.yaml > ../manifests/managed/auto-approver.yaml
