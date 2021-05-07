#!/usr/bin/env bash
set -ex
if [[ ! -f /boot/mac_addresses ]] ; then
  echo "no mac address configuration file found .. exiting"
  exit 1
fi
if [[ $(nmcli conn | grep -c brcnv) -eq 0 ]]; then
  echo "configure cnv bridge+bond"
  primary_mac=$(cat /boot/mac_addresses | awk -F= '/PRIMARY_MAC/ {print $2}')
  secondary_mac=$(cat /boot/mac_addresses | awk -F= '/SECONDARY_MAC/ {print $2}')
  default_device=""
  secondary_device=""
  profile_name=""
  secondary_profile_name=""
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


  nmcli conn add type bridge ifname brcnv con-name brcnv 802-3-ethernet.cloned-mac-address $mac ipv4.method auto ipv4.dhcp-client-id "mac" connection.autoconnect no bridge.stp no
  nmcli conn add type bond ifname bond0 con-name bond0 bond.options "mode=balance-alb,tlb_dynamic_lb=0,miimon=100,xmit_hash_policy=5" master brcnv connection.autoconnect no
  nmcli conn add type ethernet ifname $default_device con-name bond0-$default_device master bond0 connection.autoconnect no
  nmcli conn add type ethernet ifname $secondary_device con-name bond0-$secondary_device master bond0 connection.autoconnect no

  nmcli conn down "$profile_name" || true
  nmcli conn mod "$profile_name" connection.autoconnect no || true
  nmcli conn down "$secondary_profile_name" || true
  nmcli conn mod "$secondary_profile_name" connection.autoconnect no || true
  if ! (nmcli conn up bond0 && nmcli conn up bond0-$default_device && nmcli conn up bond0-$secondary_device); then
      nmcli conn up "$profile_name" || true
      nmcli conn mod "$profile_name" connection.autoconnect yes
      nmcli conn up "$secondary_profile_name" || true
      nmcli conn mod "$secondary_profile_name" connection.autoconnect yes
      nmcli c delete $(nmcli c show |grep ovs-cnv |awk '{print $1}') || true
  else
      ip link set bond0 down
      echo 0 > /sys/class/net/bond0/bonding/tlb_dynamic_lb
      ip link set bond0 up
      nmcli conn mod brcnv connection.autoconnect yes
      nmcli conn mod bond0 connection.autoconnect yes
      nmcli conn mod bond0-$default_device connection.autoconnect yes
      nmcli conn mod bond0-$secondary_device connection.autoconnect yes
  fi
else
    echo "bridge+bond already present"
fi

