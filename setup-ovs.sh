#!/usr/bin/env bash

set -ex

if [[ ! -f /boot/mac_addresses ]] ; then
  echo "no mac address configuration file found .. exiting"
  exit 1
fi

if [[ $(nmcli conn | grep -c ovs) -eq 0 ]]; then
  echo "configure ovs bonding"
  primary_mac=$(cat /boot/mac_addresses | awk -F= '/PRIMARY_MAC/ {print $2}')
  secondary_mac=$(cat /boot/mac_addresses | awk -F= '/SECONDARY_MAC/ {print $2}')
  
  default_device=""
  secondary_device=""
  profile_name=""
  secondary_profile_name=""
  
cp -r /boot/system-connections-merged /etc/NetworkManager/
Systemctl restart NetworkManger
  
  for dev in $(nmcli device status | awk '/ethernet/ {print $1}'); do
    dev_mac=$(nmcli -g GENERAL.HWADDR dev show $dev | sed -e 's/\\//g' | tr '[A-Z]' '[a-z]')
    case $dev_mac in
      $primary_mac)
        default_device=$dev
        profile_name=$(nmcli -g GENERAL.CONNECTION dev show $dev)
        ;;
      $secondary_mac)
        secondary_device=$dev
        secondary_profile_name=$(nmcli -g GENERAL.CONNECTION dev show $dev)
        ;;
      *)
        ;;
     esac
  done
  echo -e "default dev: $default_device ($profile_name)\nsecondary dev: $secondary_device ($secondary_profile_name)"
  
  mac=$(sudo nmcli -g GENERAL.HWADDR dev show $default_device | sed -e 's/\\//g')
  
  # make bridge
  nmcli conn add type ovs-bridge conn.interface brcnv 802-3-ethernet.cloned-mac-address $mac
  nmcli conn add type ovs-port conn.interface brcnv-port master brcnv
  nmcli conn add type ovs-interface \
                 conn.id brcnv-iface \
                 conn.interface brcnv master brcnv-port \
                 ipv4.method auto \
                 ipv4.dhcp-client-id "mac" \
                 connection.autoconnect no
  
  # make bond
  nmcli conn add type ovs-port conn.interface bond0 master brcnv ovs-port.bond-mode balance-slb
  nmcli conn add type ethernet conn.interface $default_device master bond0
  nmcli conn add type ethernet conn.interface $secondary_device master bond0
  nmcli conn down "$profile_name" || true
  nmcli conn mod "$profile_name" connection.autoconnect no || true
  nmcli conn down "$secondary_profile_name" || true
  nmcli conn mod "$secondary_profile_name" connection.autoconnect no || true
  if ! nmcli conn up brcnv-iface; then
      nmcli conn up "$profile_name" || true
      nmcli conn mod "$profile_name" connection.autoconnect yes
      nmcli conn up "$secondary_profile_name" || true
      nmcli conn mod "$secondary_profile_name" connection.autoconnect yes
      nmcli c delete $(nmcli c show |grep ovs-cnv |awk '{print $1}') || true
  else
      nmcli conn mod brcnv-iface connection.autoconnect yes
      cp -r /etc/NetworkManager/system-connections-merged /boot/
      reboot
  fi
else
    echo "ovs bridge already present"
fi
