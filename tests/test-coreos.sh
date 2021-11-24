#!/usr/bin/env bash

set -ex

RHCOS_SLB_REPO_URL=https://github.com/coreos/coreos-assembler.git
RHCOS_SLB_TEST_PATH=mantle/kola/tests/misc/network.go
TESTS_LIST=(rhcos.network.multiple-nics rhcos.network.init-interfaces-test)
TMP_COREOS_ASSEMBLER_PATH=$(mktemp -d -u -p /tmp -t coreos-assembler-XXXXXX)
IMAGE_PATH=/tmp/rhcos-latest-image
SCRIPT_FOLDER=$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)
RHCOS_SLB_REPO_PATH=${SCRIPT_FOLDER%/*}

source ${SCRIPT_FOLDER}/yaml-utils.sh

create_artifacts_path() {
  local tmp_dir=$1
  export ARTIFACTS=${ARTIFACTS-${tmp_dir}/artifacts}
  mkdir -p ${ARTIFACTS}
}

fetch_repo() {
  local destination=$1
  local url=$2
  local commit=$3

  if [ ! -d ${destination} ]; then
    mkdir -p ${destination}
    git clone -q ${url} ${destination}
  fi

  (
    cd ${destination}
    git reset ${commit} --hard
  )
}

fetch_latest_rhcos_image() {
  local image_path=$1
  local image_url="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest"
  local latest_image_gz=$(curl ${image_url}/ | grep -Po "rhcos-([[:digit:]]).([[:digit:]]){1,2}.([[:digit:]]{1,2})-x86_64-qemu.x86_64.qcow2.gz" | head -1)
  if [[ -z "${latest_image_gz}" ]]; then
    echo failed to get the latest image name. check url and regex
    exit 1
  fi
  local image_name=${latest_image_gz%.gz}

  local shasum=$(curl ${image_url}/sha256sum.txt | grep ${latest_image_gz} | awk '{print $1;}')
  if [[ -z "${shasum}" ]]; then
    echo failed to get the latest image shasum. check url and regex
    exit 1
  fi

  if [[ $(echo "${shasum} ${image_path}/${latest_image_gz}" | sha256sum --check) != "${image_path}/${latest_image_gz}: OK" ]]; then
    mkdir -p ${image_path}
    rm -rf ${image_path}/*
    wget -nv -O ${image_path}/${latest_image_gz} ${image_url}/${latest_image_gz}
  fi

  gzip -dk --force ${image_path}/${latest_image_gz}
  echo ${image_path}/${image_name}
}

prepare_ignition() {
  local coreos_ci_scripts_path=$1
  local capture_macs_script=${coreos_ci_scripts_path}/capture-macs.sh
  local create_datastore_script=${coreos_ci_scripts_path}/create-datastore.sh
  local ignition_fcc_tmpl=${coreos_ci_scripts_path}/custom-config.fcc.tmpl
  local ignition_fcc=${coreos_ci_scripts_path}/custom-config.fcc
  local ignition_ign=${coreos_ci_scripts_path}/custom-config.ign

  # Inject scripts to ignition_fcc_tmpl and save it to ignition_fcc file
  export base64_capture_macs_script_content=$(cat ${capture_macs_script} | base64 -w 0) && \
  export base64_create_datastore_script_content=$(cat ${create_datastore_script} | base64 -w 0) && \
  envsubst < ${ignition_fcc_tmpl} > ${ignition_fcc}

  # Finally, convert ignition_fcc to ign format on the coreos-ci repo
  docker run -i --rm quay.io/coreos/butane:release --pretty < "$ignition_fcc" > "$ignition_ign"
}

replace_network_tests() {
  local rhcos_slb_test_path=$1
  local coreos_ci_test_path=$2

  # Copy network test to coreos-ci
  cp --remove-destination ${rhcos_slb_test_path} ${coreos_ci_test_path}
}

generate_junit_from_tap_file() {
  local output_path_relative_to_mantle=$1
  npx tap-junit --pretty -i ${output_path_relative_to_mantle}/test.tap -o _kola_temp -n "junit.xml" || true
}

print_test_results() {
  local test_output=$1
  cat ${test_output}
}

expect_tests_to_succeed() {
  local test_output=$1
  if [[ -n "$(grep "FAIL:" ${test_output})" ]]; then
    exit 1
  else
    echo "tests passed"
  fi
}

run_tests() {
  local latest_image=$1
  local test_output=$2
  ./bin/kola run -b rhcos --qemu-image "${latest_image}" "${TESTS_LIST[@]}" >"${test_output}"
}

run_test_suite() {
  local latest_image=$1

  cd mantle && make >/dev/null
  test_output=${TMP_COREOS_ASSEMBLER_PATH}/tests_output
  run_tests ${latest_image} ${test_output} || true

  generate_junit_from_tap_file "$(grep -o '_kola_temp/[[:print:]]*' ${test_output})"

  print_test_results ${test_output}

  expect_tests_to_succeed ${test_output}
}

teardown() {
  echo "Copying test artifacts to ${ARTIFACTS}"
  cp -r ${TMP_COREOS_ASSEMBLER_PATH}/mantle/_kola_temp/* ${ARTIFACTS} || true
}

copy_segment_interfaces_systemd_units_contents() {
  local mco=$1
  local systemd_units_contents_file=$2

  # extract the systemd.unit segment from mco template for script-specific tests
  yaml-utils::yq ".spec.config.systemd.units[] | select(.name == \"setup-ovs.service\") | .contents" "${mco}" > "${systemd_units_contents_file}"
  if [[ ! -s "${systemd_units_contents_file}" ]]; then
    echo "error: ${systemd_units_contents_file} file empty or does not exists"
    exit 1
  fi
}

modify_interfaces_script_for_tests() {
  local interfaces_script=$1

  # Remove the exit fail if macs file in not in place, since kargs are added only after second reboot.
  sed -i 's|exit 1|exit 0|g' ${interfaces_script}
}

prepare_init_interfaces() {
  local scripts_path=$1

  modify_interfaces_script_for_tests ${scripts_path}/init-interfaces.sh

  modify_interfaces_systemd_units_contents ${scripts_path}/mco_ovs_workers.yml.tmpl

  copy_segment_interfaces_systemd_units_contents ${scripts_path}/mco_ovs_workers.yml.tmpl ${scripts_path}/init-interfaces-systemd-units-contents
}

# modify_capture_macs_script_for_tests performs modifications needed for the tests to pass on the cosa-ci platform
modify_capture_macs_script_for_tests() {
  local capture_macs_script=$1

  # Allow /boot remount with rw permissions since in cosa-ci /boot is mounted with ro permissions.
  sed -i 's|mount "/dev/disk/by-label/boot"|mount -o rw,remount|g' ${capture_macs_script}

  # Remove the exit fail if macs file in not in place, since kargs are added only after second reboot.
  sed -i 's|exit 1|exit 0|g' ${capture_macs_script}
}

modify_interfaces_systemd_units_contents() {
  local mco=$1

  # schedule the script to run after capture-macs.service
  sed -i 's|After=NetworkManager.service|After=NetworkManager.service capture-macs.service|g' ${mco}
}

copy_segment_captured_macs_systemd_units_contents() {
  local config_fcc=$1
  local systemd_units_contents_file=$2

  # extract the systemd.units.contents segment from custom-config template for script-specific tests
  echo "$(yaml-utils::yq ".systemd.units[] | select(.name == \"capture-macs.service\") | .contents" "${config_fcc}")" > ${systemd_units_contents_file}
  if [[ ! -s "${systemd_units_contents_file}" ]]; then
    echo "error: ${systemd_units_contents_file} file empty or does not exists"
    exit 1
  fi
}

modify_capture_macs_systemd_units_contents() {
  local config_fcc=$1

  # Plant RequiresMountsFor in capture-macs Unit requirements to ensure boot is mounted before script runs
  sed -i 's|Description=Capture|RequiresMountsFor=/boot\n        Description=Capture|g' ${config_fcc}

  # Plant MountFlags to ensure /boot is mounted as slave
  sed -i 's|ExecStart=/usr/local/bin/capture-macs|MountFlags=slave\n        ExecStart=/usr/local/bin/capture-macs|g' ${config_fcc}

  # Remove ConditionKernelCommandLine that is not used
  sed -i 's|ConditionKernelCommandLine=custom-config||g' ${config_fcc}

  # Replace RequiredBy systemd condition, as coreos-*.targets are not used on the tested image
  sed -i 's|RequiredBy=coreos-installer.target|RequiredBy=multi-user.target|g' ${config_fcc}
}

prepare_capture_macs() {
  local scripts_path=$1

  modify_capture_macs_script_for_tests ${scripts_path}/capture-macs.sh

  modify_capture_macs_systemd_units_contents ${scripts_path}/custom-config.fcc.tmpl ${scripts_path}/capture-macs-systemd-units-contents

  copy_segment_captured_macs_systemd_units_contents ${scripts_path}/custom-config.fcc.tmpl ${scripts_path}/capture-macs-systemd-units-contents
}

prepare_dhcp_config() {
  local scripts_path=$1

  # Remove 10-dhcp-config.conf config to not break test infra connectivity
  sed -i 's|path: /etc/NetworkManager/conf.d/10-dhcp-config.conf|path: /tmp/10-dhcp-config.conf|g' ${scripts_path}/custom-config.fcc.tmpl
}

copy_relevant_scripts_to_coreos_folder() {
  local rhcos_slb_repo_path=$1
  local coreos_ci_scripts_path=$2

  mkdir -p ${coreos_ci_scripts_path}

  # Copy ignition_fcc template to coreos-ci scripts folder
  cp ${rhcos_slb_repo_path}/custom-config.fcc.tmpl ${coreos_ci_scripts_path}

  # Copy capture-macs.sh to coreos-ci scripts folder
  cp ${rhcos_slb_repo_path}/capture-macs.sh ${coreos_ci_scripts_path}

  # Copy init-interfaces.sh to coreos-ci scripts folder
  cp ${rhcos_slb_repo_path}/init-interfaces.sh ${coreos_ci_scripts_path}

  # Copy create-datastore.sh to coreos-ci scripts folder
  cp ${rhcos_slb_repo_path}/create-datastore.sh ${coreos_ci_scripts_path}

  # Copy mco_ovs_workers.yml.tmpl to coreos-ci scripts folder
  cp ${rhcos_slb_repo_path}/mco_ovs_workers.yml.tmpl ${coreos_ci_scripts_path}
}

prepare_scripts_for_tests() {
  local coreos_ci_scripts_path=$1

  prepare_capture_macs ${coreos_ci_scripts_path}

  prepare_init_interfaces ${coreos_ci_scripts_path}

  prepare_dhcp_config ${coreos_ci_scripts_path}

  prepare_ignition ${coreos_ci_scripts_path}
}

setup_test_suite() {
  local coreos_ci_scripts_path=${TMP_COREOS_ASSEMBLER_PATH}/mantle/rhcos-scripts

  replace_network_tests "${RHCOS_SLB_REPO_PATH}"/tests/network.go "${TMP_COREOS_ASSEMBLER_PATH}"/"${RHCOS_SLB_TEST_PATH}"

  copy_relevant_scripts_to_coreos_folder ${RHCOS_SLB_REPO_PATH} ${coreos_ci_scripts_path}

  prepare_scripts_for_tests ${coreos_ci_scripts_path}
}

fetch_repo ${TMP_COREOS_ASSEMBLER_PATH} ${RHCOS_SLB_REPO_URL} main
cd ${TMP_COREOS_ASSEMBLER_PATH}

create_artifacts_path ${TMP_COREOS_ASSEMBLER_PATH}
trap teardown EXIT SIGINT SIGTERM

latest_image=$(fetch_latest_rhcos_image ${IMAGE_PATH})

setup_test_suite

run_test_suite ${latest_image}
