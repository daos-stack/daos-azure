#!/usr/bin/env bash
# Copyright (c) 2024 Intel Corporation All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -eo pipefail

trap 'echo "${BASH_SOURCE[0]} : Unexpected error. Exiting."' ERR

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
GCI_ARCHIVE_DIR=""
GCI_START_SCRIPT=""
GCI_START_ENV_FILE=""
GCI_TARGET_DIR=""
GCI_OUT_FILE=""
GCI_SCRIPT_LABEL="Cloudinit_script"
GCI_CLEANUP="true"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_log.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_inc.sh"

show_help() {

  echo "

Create cloud init for VMs

Makes a self-extracting executable file from files in a directory. The file
will be intended to be used as cloud-init script for VMs.

Before creating the self-extracting file this script will create a file named
daos-azure.env in the directory to be included in the archive. The daos-azure.env
file will contain all environment variables that have a DAOS_AZ prefix.

Usage:

  ${SCRIPT_FILE} [<options>]

Options:

  [ -d | --archive-dir ]                Directory containing files to be
                                        included in self-extracting cloud-init.
  [ -s | --start-script ]               Name of the script in the directory
                                        that will be executed when the cloud-init
                                        is run. Path can be either absolute or
                                        relative.
  [ -t | --target-dir ]                 Directory where self-extracting cloud-init
                                        will be extracted.
  [ -o | --out-file ]                   Absolute or relative path of the
                                        cloud-init file that will be generated.
  [ -h | --help ]                       Show this help

"
}

opts() {
  if [ $# -eq 0 ]; then
    show_help
    exit 0
  fi
  # shift will cause the script to exit if attempting to shift beyond the
  # max args.  So set +e to continue processing when shift errors.
  set +e
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --help | -h)
      show_help
      exit 0
      ;;
    --archive-dir | -d)
      GCI_ARCHIVE_DIR="$2"
      shift 2
      ;;
    --start-script | -s)
      GCI_START_SCRIPT="$2"
      GCI_START_ENV_FILE="${GCI_START_SCRIPT%.*}.env"
      shift 2
      ;;
    --target-dir | -t)
      # shellcheck disable=SC2034
      GCI_TARGET_DIR="$2"
      shift 2
      ;;
    --out-file | -o)
      GCI_OUT_FILE="$2"
      shift 2
      ;;
    --no-clean)
      GCI_CLEANUP="false"
      shift
      ;;
    --)
      break
      ;;
    --* | -*)
      log.error "Unrecognized option '${1}'"
      show_help
      exit 1
      ;;
    *)
      break
      ;;
    esac
  done
  set -e

  local gci_vars
  readarray -t gci_vars < <(compgen -A variable | grep "GCI_" | sort)
  for var in "${gci_vars[@]}"; do
    log.debug "${var}=\"${!var}\""
  done
}

create_vm_env_file() {
  local env_file="${GCI_ARCHIVE_DIR}/${GCI_START_ENV_FILE}"
  log.debug "Creating ${env_file}"
  local daos_vars
  touch "${env_file}"
  readarray -t daos_vars < <(compgen -A variable | grep "DAOS_" | sort)
  for var in "${daos_vars[@]}"; do
    [[ "${var^^}" == "DAOS_AZ_ARM_NSG_RULES" ]] && continue
    value="${!var}"
    if [[ ${value:0:1} == '[' ]]; then
      # If the value starts with [, do not quote it
      echo "export ${var}=${value}" >> "${env_file}"
    else
      # Otherwise, quote it
      echo "export ${var}=\"${value}\"" >> "${env_file}"
    fi
  done
}

gen_cloud_init() {
  local out_dir
  out_dir="$(dirname "${GCI_OUT_FILE}")"
  local ci_script_tmp
  ci_script_tmp="${GCI_OUT_FILE%.*}_$(date +"%Y-%m-%d_%H-%M-%S").sh"
  cd "${out_dir}"

  makeself --noprogress -q --needroot --nocrc --nomd5 --base64 \
    "${GCI_ARCHIVE_DIR}" \
    "${ci_script_tmp}" \
    "${GCI_SCRIPT_LABEL}" \
    "./${GCI_START_SCRIPT}"

  sed -i '1d;4d' "${ci_script_tmp}"
  echo "#!/bin/bash" > "${ci_script_tmp}.str"
  echo "export SETUP_NOCHECK=1" >> "${ci_script_tmp}.str"
  cat "${ci_script_tmp}" >> "${ci_script_tmp}.str"
  cp -f "${ci_script_tmp}.str" "${GCI_OUT_FILE}"
  chmod +x "${GCI_OUT_FILE}"
  if [[ "${GCI_CLEANUP,,}" == "true" ]]; then
    rm -f "${ci_script_tmp}"
    rm -f "${ci_script_tmp}.str"
    rm -f "${GCI_ARCHIVE_DIR}/${GCI_START_ENV_FILE}"
  fi
  log.info "Generated cloud-init script: ${GCI_OUT_FILE}"
}

main() {
  opts "$@"
  create_vm_env_file
  gen_cloud_init
}

main "$@"
