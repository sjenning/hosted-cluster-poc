#!/bin/bash

set -e

REPODIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/../.."

source "${REPODIR}/config.sh"

pushd ${REPODIR}/ignition-generator
./make-ignition.sh
#FIXME: hardcoded
scp final.ign fedora@api.lab:/var/www/html
popd

pushd ${REPODIR}/contrib/openstack
ansible-playbook create-workers.yaml
popd
