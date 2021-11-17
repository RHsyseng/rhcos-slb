#!/bin/bash

LABEL=datastore
OFFSET=120G

set -euo pipefail

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

# Get install device
device="$(karg coreos.inst.install_dev)"
if [[ -z $device ]]; then
		echo "Install device not specified."
		exit 1
fi
# Append /dev/ if missing
device="/dev/${device##/dev/}"

# Wait for device nodes
udevadm settle

# Check for partitions other than the system ones
if lsblk --pairs --output NAME,TYPE,PARTLABEL "${device}" |\
		awk '/TYPE="part"/ && !/PARTLABEL="(boot|EFI-SYSTEM|BIOS-BOOT|root|luks_root)"/ {print; exit 1}'
then
		echo "Creating data partition \"${LABEL}\""

		# Relocate second GPT header to end of disk and create partition
		sgdisk --move-second-header \
				--new=0:+"${OFFSET}":0 --change-name=0:"${LABEL}" \
				"${device}"

		# Wait for device node
		udevadm settle
else
		echo "Found existing data partition; not creating a new one"
fi
