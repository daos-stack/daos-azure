#!/usr/bin/env bash
# shellcheck disable=SC2155
# shellcheck disable=SC1090

set -eo pipefail

trap 'echo "An error occurred. Exiting ..."; exit 1' ERR SIGINT

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
DEFAULT_ENV_FILE="$(realpath "${SCRIPT_DIR}/../daos-azure.env")"

source "${SCRIPT_DIR}/../bin/_log.sh"

export_vars() {
  readarray -t pkr_vars < <(compgen -A variable | grep "DAOS_" | sort)
  for var in "${pkr_vars[@]}"; do
    export "$var"
  done
}

create_packer_vars_file() {
  log.info "Creating pkrvars file: ${DAOS_AZ_PKR_VARS_FILE_PATH}"
  envsubst <"${DAOS_AZ_PKR_VARS_ENVTPL_FILE_PATH}" >"${DAOS_AZ_PKR_VARS_FILE_PATH}"
}

# Load environment variables from the file specified in DAOS_AZ_ENV_FILE if it
# has been set. This allows for different image build configurations to be
# stored in files outside of the repo so that custom images can be built for
# testing.
source_build_env_file() {
  local env_file="${1:-"${DEFAULT_ENV_FILE}"}"
  log.debug "env_file=${env_file}"
  if [[ -n $env_file ]]; then
    if [[ -f "${env_file}" ]]; then
      log.debug "Sourcing ${env_file}"
      source "${env_file}"
    else
      log.error "ERROR File not found: ${env_file}"
      exit 1
    fi
  else
    log.debug "DAOS_AZ_ENV_FILE=${DAOS_AZ_ENV_FILE}"
    log.debug "Checking for existence of ${DAOS_AZ_ENV_FILE}"
    if [[ -f "${DAOS_AZ_ENV_FILE}" ]]; then
      log.debug "Sourcing ${DAOS_AZ_ENV_FILE}"
      source "${DAOS_AZ_ENV_FILE}"
    fi
  fi

  DAOS_AZ_PKR_TEMPLATE_PATH="${SCRIPT_DIR}/${DAOS_AZ_PKR_TEMPLATE_FILE}"
  DAOS_AZ_PKR_VARS_FILE_PATH="${SCRIPT_DIR}/${DAOS_AZ_PKR_TEMPLATE_FILE%.*}vars.hcl"
  DAOS_AZ_PKR_VARS_ENVTPL_FILE_PATH="${SCRIPT_DIR}/${DAOS_AZ_PKR_TEMPLATE_FILE%.*}vars.hcl.envtpl"

  export_vars
  log.debug.vars
}

run_packer() {
  [[ "${DAOS_AZ_LOG_LEVEL}" == "DEBUG" ]] && PACKER_LOG=1
  log.info "Running packer to build image"
  packer init -var-file="${DAOS_AZ_PKR_VARS_FILE_PATH}" "${DAOS_AZ_PKR_TEMPLATE_PATH}"
  packer build -force -var-file="${DAOS_AZ_PKR_VARS_FILE_PATH}" "${DAOS_AZ_PKR_TEMPLATE_PATH}"
}

show_images() {
  log.info "List Image(s)"

  az sig image-version list \
    --gallery-image-definition "${DAOS_AZ_PKR_DEST_IMG_NAME}" \
    --gallery-name "${DAOS_AZ_PKR_DEST_IMG_GAL_NAME}" \
    --resource-group "${DAOS_AZ_PKR_DEST_IMG_GAL_RG_NAME}"
}

cleanup() {
  log.info "Running cleanup ..."
  if [[ -f "${DAOS_AZ_PKR_VARS_FILE_PATH}" ]]; then
    rm -f "${DAOS_AZ_PKR_VARS_FILE_PATH}"
  fi
}

main() {
  source_build_env_file "$@"
  export_vars
  log.debug.vars
  create_packer_vars_file
  run_packer
  show_images
  cleanup
}

main "$@"
