#!/bin/bash

set -ex

OUT_DIR=$1

build_custom_config() {
	local output_fcc=${OUT_DIR}/custom-config.fcc
	local output_ign=${OUT_DIR}/custom-config.ign

	# Base64 encode the `capture-macs.sh` file
	base64_capture_macs_script_content=$(base64 -w 0 < capture-macs.sh) && export base64_capture_macs_script_content
	# Base64 encode the `create-datastore.sh` file
	base64_create_datastore_script_content=$(base64 -w 0 < create-datastore.sh) && export base64_create_datastore_script_content

	# Paste the content into custom-config.fcc
	envsubst \$base64_capture_macs_script_content,\$base64_create_datastore_script_content <  custom-config.fcc.tmpl > "${output_fcc}"

  docker run -i --rm quay.io/coreos/butane:release --pretty < "${output_fcc}" > "${output_ign}"
}

build_mco() {
  local output_worker_mco=${OUT_DIR}/mco_ovs_workers.yml
  local output_supervisor_mco=${OUT_DIR}/mco_ovs_supervisor.yml

  # Base64 encode the `init-interfaces.sh` file
  export base64_script_content=$(base64 -w 0 < init-interfaces.sh)

  # Paste the content into each MCO file
  envsubst < mco_ovs_workers.yml.tmpl > "${output_worker_mco}"
  envsubst < mco_ovs_supervisor.yml.tmpl > "${output_supervisor_mco}"
}

if [[ ! -d "${OUT_DIR}" ]]; then
  mkdir -p "${OUT_DIR}"
fi

build_custom_config

build_mco
