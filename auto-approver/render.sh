#!/bin/bash

set -eu

source ../config.sh
source ../lib/common.sh

export CLI_IMAGE=$(image_for cli)
envsubst '$CLI_IMAGE' < auto-approver.yaml > ../manifests/managed/auto-approver.yaml
