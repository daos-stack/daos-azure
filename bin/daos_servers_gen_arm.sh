#!/usr/bin/env bash

set -eo pipefail

trap 'echo "${BASH_SOURCE[0]} : Unexpected error. Exiting."' ERR

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")

DEFAULT_ENV_FILE="${SCRIPT_DIR}/../daos-azure.env"
DAOS_AZ_ENV_FILE="${DAOS_AZ_ENV_FILE:="${DEFAULT_ENV_FILE}"}"

ARM_DIR="$(realpath "${SCRIPT_DIR}/../arm/daos")"
VM_FILES_DIR="$(realpath "${SCRIPT_DIR}/../vm_files")"
VM_FILES_DIR_SERVER="${VM_FILES_DIR}/daos_server"

DAOS_AZ_ARM_SVR_SRC_TEMPLATE="${DAOS_AZ_ARM_SRC_TEMPLATE:="azuredeploy_server_template.json"}"
DAOS_AZ_ARM_SVR_DEST_TEMPLATE="${DAOS_AZ_ARM_DEST_TEMPLATE:="azuredeploy_server.json"}"

# Logging functions
source "${SCRIPT_DIR}/_log.sh"

export_vars() {
  readarray -t pkr_vars < <(compgen -A variable | grep "DAOS_" | sort)
  for var in "${pkr_vars[@]}"; do
    export "$var"
  done
}

source_build_env_file() {
  local env_file="${1}"
  if [[ -n "${env_file}" ]]; then
    if [[ -f "${env_file}" ]]; then
      log.debug "Sourcing ${env_file}"
      source "${env_file}"
    else
      log.error "ERROR File not found: ${env_file}"
      exit 1
    fi
  else
    log.debug "Checking for existence of ${DAOS_AZ_ENV_FILE}"
    if [[ -f "${DAOS_AZ_ENV_FILE}" ]]; then
      log.debug "Sourcing ${DAOS_AZ_ENV_FILE}"
    else
      log.error "File not found: ${DAOS_AZ_ENV_FILE}"
      exit 1
    fi
  fi
  export_vars
}

create_entry_script_env_files() {
  cat >"${VM_FILES_DIR_SERVER}/daos_server_setup.env" <<EOF
DAOS_AZ_CORE_ACCT_NAME="${DAOS_AZ_CORE_ACCT_NAME}"
DAOS_AZ_CORE_ACCT_ID="${DAOS_AZ_CORE_ACCT_ID}"
DAOS_AZ_CORE_RG_NAME="${DAOS_AZ_CORE_RG_NAME}"
DAOS_AZ_CORE_LOCATION="${DAOS_AZ_CORE_LOCATION}"
DAOS_AZ_CORE_ANS_COL_URL="${DAOS_AZ_CORE_ANS_COL_URL}"
DAOS_AZ_CORE_RESOURCE_PREFIX="${DAOS_AZ_CORE_RESOURCE_PREFIX}"
DAOS_AZ_ARM_SVR_VMSS_NAME="${DAOS_AZ_ARM_SVR_VMSS_NAME}"
DAOS_AZ_SSH_ADMIN_KEY_PUB_DATA="${DAOS_AZ_SSH_ADMIN_KEY_PUB_DATA}"
DAOS_AZ_ARM_ADMIN_USER="${DAOS_AZ_ARM_ADMIN_USER}"
DAOS_AZ_ARM_KEY_VAULT_NAME="${DAOS_AZ_ARM_KEY_VAULT_NAME}"
DAOS_AZ_CFG_ALLOW_INSECURE="${DAOS_AZ_CFG_ALLOW_INSECURE}"
DAOS_AZ_CFG_NR_HUGEPAGES=${DAOS_AZ_CFG_NR_HUGEPAGES}
DAOS_AZ_CFG_SCM_SIZE_GB=${DAOS_AZ_CFG_SCM_SIZE_GB}
DAOS_AZ_CFG_TARGETS=${DAOS_AZ_CFG_TARGETS}
DAOS_AZ_CFG_NR_XS_HELPERS=${DAOS_AZ_CFG_NR_XS_HELPERS}
DAOS_AZ_CFG_CONTROL_LOG_MASK="${DAOS_AZ_CFG_CONTROL_LOG_MASK}"
DAOS_AZ_POOL_NAME="${DAOS_AZ_POOL_NAME}"
DAOS_AZ_POOL_SIZE="${DAOS_AZ_POOL_SIZE}"
EOF
}

gen_arm_template() {

  local ci_script_svr="cloudinit_svr_$(date +"%Y-%m-%d_%H-%M-%S").sh"

  cd "${SCRIPT_DIR}"

  # Server script
  makeself --nocomp --nocrc --nomd5 --base64 "${VM_FILES_DIR_SERVER}" "${ci_script_svr}" "Cloudinit_script" "./daos_server_setup.sh"
  sed -i '1d;4d' "${ci_script_svr}"
  echo "[concat('#!/bin/bash" >${ci_script_svr}.str
  echo -n "set --'," >>${ci_script_svr}.str

  while test $# -gt 0; do
    echo -n "' \"',parameters('$1'),'\"'," >>${ci_script_svr}.str
    shift
  done
  echo "'" >>${ci_script_svr}.str
  echo -n "','" >>${ci_script_svr}.str
  sed "s/'/''/g" ${ci_script_svr} >>${ci_script_svr}.str
  echo -n "')]" >>${ci_script_svr}.str

  local arm_src_file_path="${ARM_DIR}/${DAOS_AZ_ARM_SRC_TEMPLATE}"
  local arm_dest_file_path="${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}"
  log.debug "arm_src_file_path=${arm_src_file_path}"
  log.debug "arm_dest_file_path=${arm_dest_file_path}"

  log.info "Running jq to create ${arm_dest_file_path}"

  jq ".variables.ciScriptServer = $(jq -Rs '.' <${ci_script_svr}.str)" \
    "${arm_src_file_path}" >"${arm_dest_file_path}"

  if [[ -f "${ci_script_svr}" ]]; then
    rm -f "${ci_script_svr}"
    rm -f "${ci_script_svr}.str"
  fi
}

cleanup() {
  if [[ -f "${VM_FILES_DIR_SERVER}/daos_server_setup.env" ]]; then
    rm -f "${VM_FILES_DIR_SERVER}/daos_server_setup.env"
  fi
}

main() {
  source_build_env_file "$@"
  create_entry_script_env_files
  gen_arm_template
  cleanup
}

main "$@"
