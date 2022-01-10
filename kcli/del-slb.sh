#!/bin/bash 

set -xe

oc apply -f del-slb-nncp.yaml
./kcli/update-keepalived.sh enx525400f68001
./kcli/retry.sh oc wait nncp slb --for=condition=Available
