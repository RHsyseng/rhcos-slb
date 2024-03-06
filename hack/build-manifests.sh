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
    if [ "${SNO_VERSION}" != "" ]; then
        build_sno_custom_config $output_fcc
    fi
    docker run -i --rm quay.io/coreos/butane:release --pretty < "${output_fcc}" > "${output_ign}"
}

build_sno_custom_config() {
    local output_fcc=$1
    local sno_output_dir=${OUT_DIR}/sno
    
    # Generate the original-master.ign from repo's customization
    mkdir -p ${sno_output_dir}
    cp "${output_fcc}" ${sno_output_dir}/original-master.fcc
    docker run -i --rm quay.io/coreos/butane:release --pretty < ${sno_output_dir}/original-master.fcc > ${sno_output_dir}/original-master.ign
    
    # The template has a "merge oringla-master.ign" directive so
    # just copy it
    local master_update_fcc_url=https://github.com/openshift/installer/raw/release-${SNO_VERSION}/data/data/bootstrap/bootstrap-in-place/files/opt/openshift/bootstrap-in-place/master-update.fcc
    curl -L "$master_update_fcc_url" > ${sno_output_dir}/master-update.fcc
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
