#!/usr/bin/env bash

set -ex

RHCOS_SLB_REPO_URL=https://github.com/coreos/coreos-assembler.git
RHCOS_SLB_TEST_PATH=mantle/kola/tests/misc/network.go
TESTS_LIST="rhcos.network.multiple-nics rhcos.network.bond-with-dhcp"
TMP_COREOS_ASSEMBLER_PATH=$(mktemp -d -u -p /tmp -t coreos-assembler-XXXXXX)
IMAGE_PATH=/tmp/rhcos-latest-image
SCRIPT_FOLDER=$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)
RHCOS_SLB_REPO_PATH=${SCRIPT_FOLDER%/*}

create_artifacts_path() {
  local tmp_dir=$1
  export ARTIFACTS=${ARTIFACTS-${tmp_dir}/artifacts}
  mkdir -p ${ARTIFACTS}/_kola_temp
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
  local latest_image_gz=$(curl ${image_url} | grep -o rhcos-[0-9].[0-9].[0-9][0-9]-x86_64-qemu.x86_64.qcow2.gz | head -1)
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

replace_setup_ovs_script() {
  local rhcos_slb_repo_path=$1
  local coreos_ci_repo_path=$2
  local coreos_ci_test_relative_path=$3
  local setup_ovs_script=${coreos_ci_repo_path}/setup-ovs.sh
  local coreos_ci_full_path=${coreos_ci_repo_path}/${coreos_ci_test_relative_path}

  # Copy setup_ovs script from rhcos_slb_repo to the coreos-ci repo
  cp ${rhcos_slb_repo_path}/setup-ovs.sh ${setup_ovs_script}
  # We need to do specific changes to the script in order for it to run on the coreos-ci
  # Remove the exit fail if macs file in not inplace.
  sed -i 's|exit 1|exit 0|g' ${setup_ovs_script}

  # Rename the current script variable in coreos-assemlber
  sed -i 's|setupOvsScript =|notUsedSetupOvsScript =|g' ${coreos_ci_full_path}
  # Add the new script to the coreos-ci instead of the old variable
  local new_ovs_script="$(cat ${setup_ovs_script})"
  echo "var setupOvsScript =\`${new_ovs_script}\`" >> ${coreos_ci_full_path}
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
  run_tests ${latest_image} ${test_output}

}

teardown() {
	echo "Copying test artifacts to ${ARTIFACTS}"
  cp -r ${TMP_COREOS_ASSEMBLER_PATH}/mantle/_kola_temp/* ${ARTIFACTS}/_kola_temp || true
}

fetch_repo ${TMP_COREOS_ASSEMBLER_PATH} ${RHCOS_SLB_REPO_URL} main
cd ${TMP_COREOS_ASSEMBLER_PATH}

create_artifacts_path ${TMP_COREOS_ASSEMBLER_PATH}
trap teardown EXIT SIGINT SIGTERM

latest_image=$(fetch_latest_rhcos_image ${IMAGE_PATH})

replace_setup_ovs_script ${RHCOS_SLB_REPO_PATH} ${TMP_COREOS_ASSEMBLER_PATH} mantle/kola/tests/misc/network.go

run_test_suite ${latest_image}
