#!/usr/bin/env bash
# To control the behavior of this script export a variable named
# DAOS_SERVERS_GEN_ARM_ENV_FILE before running this script.
# DAOS_SERVERS_GEN_ARM_ENV_FILE should contain a path of a file that
# contains env vars to override settings for this script.

set -eo pipefail

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
SCRIPT_ENV_FILE="${DAOS_SERVERS_GEN_ARM_ENV_FILE:="${SCRIPT_FILE%.*}.env"}"
ARM_DIR="$(realpath ${SCRIPT_DIR}/../arm/daos)"
VM_FILES_DIR="$(realpath "${SCRIPT_DIR}/../vm_files/daos_server")"

[[ -f "${SCRIPT_ENV_FILE}" ]] && . "${SCRIPT_ENV_FILE}"

DAOS_AZ_RESOURCE_PREFIX="${DAOS_AZ_RESOURCE_PREFIX:="${USER}"}"
DAOS_AZ_ARM_SRC_TEMPLATE="${DAOS_AZ_ARM_SRC_TEMPLATE:="azuredeploy_server_template.json"}"
DAOS_AZ_ARM_DEST_TEMPLATE="${DAOS_AZ_ARM_DEST_TEMPLATE:="azuredeploy_server.json"}"
DAOS_VM_FILES_DIR="${DAOS_VM_FILES_DIR:="${VM_FILES_DIR}"}"
DAOS_VM_ENTRY_SCRIPT="${DAOS_VM_ENTRY_SCRIPT:="daos_server_setup.sh"}"
DAOS_VM_BASE_NAME="${DAOS_VM_BASE_NAME:="${DAOS_AZ_RESOURCE_PREFIX}-daos-server"}"
DAOS_SCM_SIZE="${DAOS_SCM_SIZE:=40}"
DAOS_AZ_serverCount="${DAOS_AZ_serverCount:=1}"

create_start_script_env_file() {
  local start_script_env_file="${DAOS_VM_FILES_DIR}/${DAOS_VM_ENTRY_SCRIPT%.*}.env"
  echo "BEGIN: get_start_script_env_file()"
  echo "start_script_env_file=${start_script_env_file}"
  cat >"${start_script_env_file}" <<EOF
DAOS_VM_BASE_NAME="${DAOS_VM_BASE_NAME}"
DAOS_AZ_serverCount=$DAOS_AZ_serverCount
DAOS_SCM_SIZE=${DAOS_SCM_SIZE}
EOF
  echo "END: get_start_script_env_file()"
}

create_cloud_init_script() {
  local ci_script="cloudinit_$(date +"%Y-%m-%d_%H-%M-%S").sh"
  echo "ci_script=$ci_script"
  # Usage: /usr/bin/makeself [params] archive_dir file_name label startup_script [args]
  makeself --nocomp --nocrc --nomd5 --base64 "${DAOS_VM_FILES_DIR}" "${ci_script}" "Cloudinit_script" "./${DAOS_VM_ENTRY_SCRIPT}"
  sed -i '1d;4d' "${ci_script}"

  echo "[concat('#!/bin/bash" >${ci_script}.str
  echo -n "set --'," >>${ci_script}.str

  while test $# -gt 0; do
    echo -n "' \"',parameters('$1'),'\"'," >>${ci_script}.str
    shift
  done
  echo "'" >>${ci_script}.str
  echo -n "','" >>${ci_script}.str
  sed "s/'/''/g" ${ci_script} >>${ci_script}.str
  echo -n "')]" >>${ci_script}.str
  local arm_src_file_path="${ARM_DIR}/${DAOS_AZ_ARM_SRC_TEMPLATE}"
  local arm_dest_file_path="${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}"
  echo "arm_src_file_path=${arm_src_file_path}"
  echo "arm_dest_file_path=${arm_dest_file_path}"
  jq ".variables.ciScript = $(jq -Rs '.' <${ci_script}.str)" "${arm_src_file_path}" >"${arm_dest_file_path}"

  if [[ -f "${ci_script}" ]]; then
    rm -f "${ci_script}"
    rm -f "${ci_script}.str"
  fi
}

echo "SCRIPT_ENV_FILE=${SCRIPT_ENV_FILE}"
create_start_script_env_file
create_cloud_init_script
