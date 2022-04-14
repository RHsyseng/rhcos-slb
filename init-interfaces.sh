#!/usr/bin/env bash

set -ex

is_configured() {
  [[ $(grep primary /etc/NetworkManager/system-connections/* | wc -l) -ge 1 && $(grep secondary /etc/NetworkManager/system-connections/* | wc -l) -ge 1 ]]
}

is_con_exists() {
  local con_name=$1
  if nmcli -t -g NAME con show | grep -w -q "$con_name"; then
    return 0 # true
  fi
  return 1 # false
}

is_con_active() {
  local con_name=$1
  if nmcli -t -g NAME con show --active | grep -w -q "$con_name"; then
    return 0 # true
  fi
  return 1 # false
}

get_con_name_by_mac_or_device() {
  local mac=$(echo $1 | sed -e 's/\\\|://g')
  local dev_name=$2
  while read -r con; do
    if [[ "$(nmcli -g 802-3-ethernet.mac-address c show "${con}" | tr '[A-Z]' '[a-z]' | sed -e 's/\\\|://g')" == "$mac" || $(nmcli -g connection.interface-name c show "${con}") == "${dev_name}" ]]; then
      echo "${con}"
      break
    fi
  done <<< "$(nmcli -g NAME c show)"
}

generate_new_con_name() {
  local device_name=$1
  printf "ethernet-%s-%s" "$device_name" "$RANDOM"
}

set_description() {
  local mac=$1
  local nic=$2
  local description=$3
  local cons=$(egrep -l -i "mac-address=$mac|interface-name=$nic" $(egrep -l "type=ethernet" /etc/NetworkManager/system-connections/*))
  for c in $cons; do
      if ! grep nmstate.interface.description $c; then
         echo "" >> $c
         echo "[user]" >> $c
         echo nmstate.interface.description=$description >> $c
      else
         sed -i "s/nmstate\.interface\.description=.*/nmstate.interface.description=$description/" $c
      fi
done
}

if [[ ! -f /boot/mac_addresses ]] ; then
  echo "no mac address configuration file found .. exiting"
  exit 1
fi

if is_configured; then
  echo "interfaces already configured"
  exit 0
fi

primary_mac="$(awk -F= '/PRIMARY_MAC/ {print $2}' < /boot/mac_addresses | tr '[:upper:]' '[:lower:]')"
secondary_mac="$(awk -F= '/SECONDARY_MAC/ {print $2}' < /boot/mac_addresses | tr '[:upper:]' '[:lower:]')"

default_device=""
secondary_device=""
default_connection_name=""
secondary_connection_name=""

for dev in $(nmcli device status | awk '/ethernet/ {print $1}'); do
  dev_mac=$(nmcli -g GENERAL.HWADDR dev show "$dev" | sed -e 's/\\//g' | tr '[:upper:]' '[:lower:]')
  case $dev_mac in
    $primary_mac)
      default_device="$dev"
      default_connection_name=$(get_con_name_by_mac_or_device "$primary_mac" "$dev")
      ;;
    $secondary_mac)
      secondary_device="$dev"
      secondary_connection_name=$(get_con_name_by_mac_or_device "$secondary_mac" "$dev")
      ;;
    *)
      ;;
   esac
done

echo -e "default dev: $default_device (CONNECTION.NAME $default_connection_name)\nsecondary dev: $secondary_device (CONNECTION.NAME $secondary_connection_name)"
if [[ -z "$default_device" ]] || [[ -z "$secondary_device" ]]; then
  echo "error: primary/secondary device name not found"
  exit 1
fi

if eval ! is_con_exists "\"$default_connection_name\""; then
  default_connection_name="$(generate_new_con_name "$default_device")" && export default_connection_name
  nmcli con add type ethernet \
                conn.interface "$default_device" \
                connection.autoconnect yes \
                ipv4.method auto \
                con-name "$default_connection_name"
fi
if eval ! is_con_active "\"$default_connection_name\""; then
  nmcli con up "$default_connection_name"
fi

if eval ! is_con_exists "\"$secondary_connection_name\""; then
  secondary_connection_name="$(generate_new_con_name "$secondary_device")" && export secondary_connection_name
  nmcli con add type ethernet \
                conn.interface "$secondary_device" \
                connection.autoconnect yes \
                ipv4.method disabled \
                ipv6.method disabled \
                con-name "$secondary_connection_name"
fi
if eval ! is_con_active "\"$secondary_connection_name\""; then
  nmcli con up "$secondary_connection_name"
fi

set_description "$primary_mac" "$default_device" primary
set_description "$secondary_mac" "$secondary_device" secondary

nmcli c reload

