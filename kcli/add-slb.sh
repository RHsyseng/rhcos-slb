#!/bin/bash 

set -xe

oc apply -f add-slb-nncp.yaml
./kcli/update-keepalived.sh brcnv-iface
./kcli/retry.sh oc wait nncp slb --for=condition=Available
