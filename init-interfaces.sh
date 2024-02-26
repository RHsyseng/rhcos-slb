#!/usr/bin/env bash

set -ex

is_configured() {
  [[ $(nmstatectl show --json bondcnv |jq '.interfaces |length') -eq 1 ]]
}

read_mac() {
  local field=$1
  awk -F= "/$field/ {print \$2}" < /boot/mac_addresses | tr '[:lower:]' '[:upper:]'
}

find_interface_by_mac() {
  local mac=$1
  nmstatectl show --json |jq -r ".interfaces[] | select(.\"mac-address\"==\"$mac\").name"
}

create_cnvnet() {
  nmstatectl apply << EOF
ovn:
  bridge-mappings:
  - localnet: cnvnet
    bridge: br-ex
EOF
}

create_bondcnv() {
  if [[ ! -f /boot/mac_addresses ]] ; then
    echo "no mac address configuration file found .. exiting"
    exit 1
  fi
  
  if is_configured; then
    echo "interfaces already configured"
    exit 0
  fi
  
  local default_device=$(find_interface_by_mac $(read_mac PRIMARY_MAC))
  local secondary_device=$(find_interface_by_mac $(read_mac SECONDARY_MAC))
  
  echo -e "default dev: $default_device \nsecondary dev: $secondary_device"
  if [[ -z "$default_device" ]] || [[ -z "$secondary_device" ]]; then
    echo "error: primary/secondary device name not found"
    exit 1
  fi

# We cannot use nmpolicy [1] or /etc/nmstate yet [2]
# [1] https://issues.redhat.com/browse/RHEL-26617
# [2] https://github.com/openshift/machine-config-operator/pull/4212
  nmstatectl apply << EOF
interfaces:
- name: bondcnv
  type: bond
  state: up
  ipv4:
    enabled: true
    dhcp: true
  copy-mac-from: $default_device
  link-aggregation:
    mode: balance-xor
    options:
      xmit_hash_policy: vlan+srcmac
      balance-slb: 1
    port:
    - $default_device
    - $secondary_device
EOF
}

$@
