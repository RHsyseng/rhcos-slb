#!/usr/bin/env bash

set -xeo pipefail

function __yq() {
  docker run --rm -i -v "${yaml_path}":/workdir --user "$UID" mikefarah/yq:4 "$@"
}

function yaml-utils::yq() {
	local eval_arg=$1
	local yaml_file=$2
	local yaml_path=${yaml_file%/*}
	local yaml_name=${yaml_file##*/}

	export yaml_path="${yaml_path}" && __yq eval "${eval_arg}" "${yaml_name}"
}
