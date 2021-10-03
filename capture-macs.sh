#!/usr/bin/env bash

set -ex

echo "Processing MAC addresses"
cmdline=( $(</proc/cmdline) )
karg() {
		local name="$1" value="${2:-}"
		for arg in "${cmdline[@]}"; do
				if [[ "${arg%%=*}" == "${name}" ]]; then
						value="${arg#*=}"
				fi
		done
		echo "${value}"
}
# Wait for device nodes
udevadm settle

macs="$(karg macAddressList)"
if [[ -z $macs ]]; then
	echo "No MAC addresses specified."
	exit 1
fi

export PRIMARY_MAC=$(echo $macs | awk -F, '{print $1}')
export SECONDARY_MAC=$(echo $macs | awk -F, '{print $2}')
mount "/dev/disk/by-label/boot" /boot
echo -e "PRIMARY_MAC=${PRIMARY_MAC}\nSECONDARY_MAC=${SECONDARY_MAC}" > /boot/mac_addresses
