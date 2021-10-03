#!/usr/bin/env bash

set -ex

RHCOS_SLB_REPO_URL=https://github.com/coreos/coreos-assembler.git
RHCOS_SLB_TEST_PATH=mantle/kola/tests/misc/network.go
TESTS_LIST="rhcos.network.multiple-nics"
TMP_COREOS_ASSEMBLER_PATH=$(mktemp -d -u -p /tmp -t coreos-assembler-XXXXXX)
IMAGE_PATH=/tmp/rhcos-latest-image
SCRIPT_FOLDER=$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)
RHCOS_SLB_REPO_PATH=${SCRIPT_FOLDER%/*}

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
  local image_url="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/latest/"
  local latest_image_gz=$(curl ${image_url} | grep -o rhcos-[0-9].[0-9].[0-9]\\+-x86_64-qemu.x86_64.qcow2.gz | head -1)
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

# modify_ignition_fcc performs some modifications on the fcc file in order to run on the coreos-ci infra
modify_ignition_fcc() {
  local rhcos_slb_repo_path=$1
  local coreos_ci_repo_path=$2
  local coreos_ci_ignition_relative_path=$3
  local rhcos_slb_capture_macs_script=${rhcos_slb_repo_path}/capture-macs.sh
  local coreos_ci_capture_macs_script=${coreos_ci_repo_path}/mantle/capture-macs.sh
  local rhcos_slb_ignition_fcc_tmpl=${rhcos_slb_repo_path}/custom-config.fcc.tmpl
  local coreos_ci_ignition_fcc_tmpl=${coreos_ci_repo_path}/custom-config.fcc.tmpl
  local coreos_ci_ignition_fcc=${coreos_ci_repo_path}/custom-config.fcc
  local coreos_ci_ignition_ign=${coreos_ci_repo_path}/${coreos_ci_ignition_relative_path}/custom-config.ign

  # Copy capture-macs.sh to coreos-ci mantle folder
  cp ${rhcos_slb_capture_macs_script} ${coreos_ci_capture_macs_script}

  # Copy ignition_fcc to coreos-ci folder
  cp ${rhcos_slb_ignition_fcc_tmpl} ${coreos_ci_ignition_fcc_tmpl}

  # Inject capture-macs script to ignition_fcc_tmpl and save it to ignition_fcc file
  export base64_capture_macs_script_content=$(cat ${coreos_ci_capture_macs_script} | base64 -w 0) && envsubst < ${coreos_ci_ignition_fcc_tmpl} > ${coreos_ci_ignition_fcc}

  # Remove the exit fail if macs file in not in place, since kargs are added only after second reboot.
  sed -i 's|exit 1|exit 0|g' ${coreos_ci_ignition_fcc}

  # Remove 10-dhcp-config.conf config to not break test infra connectivity
  sed -i 's|path: /etc/NetworkManager/conf.d/10-dhcp-config.conf|path: /tmp/10-dhcp-config.conf|g' ${coreos_ci_ignition_fcc}

  # Remove ConditionKernelCommandLine that is not used
  sed -i 's|ConditionKernelCommandLine=custom-config||g' ${coreos_ci_ignition_fcc}

  # Remove Before systemd condition, as coreos-*.targets are not used on the tested image
  sed -i 's|Before=coreos-installer.target||g' ${coreos_ci_ignition_fcc}

  # Replace After systemd condition, as coreos-*.targets are not used on the tested image
  sed -i 's|After=create-datastore.service|After=network-online.target|g' ${coreos_ci_ignition_fcc}

  # Replace RequiredBy systemd condition, as coreos-*.targets are not used on the tested image
  sed -i 's|RequiredBy=coreos-installer.target|RequiredBy=multi-user.target|g' ${coreos_ci_ignition_fcc}

  # Finally, convert ignition_fcc to ign format on the coreos-ci repo
  docker run -i --rm quay.io/coreos/butane:release --pretty < "$coreos_ci_ignition_fcc" > "$coreos_ci_ignition_ign"
}

replace_network_tests() {
  local rhcos_slb_repo_path=$1
  local rhcos_slb_test_relative_path=$2
  local coreos_ci_repo_path=$3
  local coreos_ci_test_relative_path=$4

  local rhcos_slb_network_test=${rhcos_slb_repo_path}/${rhcos_slb_test_relative_path}/network.go
  local coreos_ci_network_test=${coreos_ci_repo_path}/${coreos_ci_test_relative_path}/network.go

  # Copy network test to coreos-ci
  cp --remove-destination ${rhcos_slb_network_test} ${coreos_ci_network_test}
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
  ./bin/kola run -b rhcos --qemu-image ${latest_image} ${TESTS_LIST} >${test_output}
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

fetch_repo ${TMP_COREOS_ASSEMBLER_PATH} ${RHCOS_SLB_REPO_URL} main
cd ${TMP_COREOS_ASSEMBLER_PATH}

create_artifacts_path ${TMP_COREOS_ASSEMBLER_PATH}
trap teardown EXIT SIGINT SIGTERM

latest_image=$(fetch_latest_rhcos_image ${IMAGE_PATH})

modify_ignition_fcc ${RHCOS_SLB_REPO_PATH} ${TMP_COREOS_ASSEMBLER_PATH} mantle

replace_network_tests ${RHCOS_SLB_REPO_PATH} tests ${TMP_COREOS_ASSEMBLER_PATH} mantle/kola/tests/misc

run_test_suite ${latest_image}
