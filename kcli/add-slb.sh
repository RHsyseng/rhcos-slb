#!/bin/bash 

set -xe

oc apply -f add-slb-nncp.yaml
./kcli/update-keepalived.sh brcnv
./kcli/retry.sh oc wait nncp slb --for=condition=Available
