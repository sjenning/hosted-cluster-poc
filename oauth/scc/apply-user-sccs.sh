#!/bin/bash

# because of the way discovery was hack for openshift types, SCCs have to
# be accessed with `oc create|get --raw`

for i in $(ls scc-*); do
  oc create --raw /apis/security.openshift.io/v1/securitycontextconstraints -f $i;
done
