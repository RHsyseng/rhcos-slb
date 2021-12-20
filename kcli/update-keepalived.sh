#!/bin/bash 

set -xe

interface=$1

# At kcli a VIP is used to expose apiserver we should change keepalive to put the VIP at the new ovs-interface
kcli ssh rhocs-slb-master-0 -- "sudo sed -i 's@interface .*@interface $interface@' /etc/kubernetes/keepalived.conf"
pod_id=$(kcli ssh rhocs-slb-master-0 -- "sudo crictl pods --namespace openshift-infra --name keepalived-rhocs-slb-master-0.qinqon.com --output json |jq -r .items[0].id")
kcli ssh rhocs-slb-master-0 -- "sudo crictl rmp --force $pod_id"
