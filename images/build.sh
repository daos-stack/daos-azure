#!/usr/bin/env bash
# shellcheck disable=SC2155
# shellcheck disable=SC1090

set -euo pipefail

trap 'error_handler' ERR SIGINT

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

: "${LOG_LEVEL:=INFO}"

# BEGIN: Logging variables and functions
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [FATAL]=4 [OFF]=5)
declare -A LOG_COLORS=([DEBUG]=2 [INFO]=12 [WARN]=3 [ERROR]=1 [FATAL]=9 [OFF]=0 [OTHER]=15)

log() {
  local msg="$1"
  local lvl=${2:-INFO}
  if [[ ${LOG_LEVELS[$LOG_LEVEL]} -le ${LOG_LEVELS[$lvl]} ]]; then
    if [[ -t 1 ]]; then tput setaf "${LOG_COLORS[$lvl]}"; fi
    printf "[%-5s] %s\n" "$lvl" "${msg}" 1>&2
    if [[ -t 1 ]]; then tput sgr0; fi
  fi
}

log.debug() { log "${1}" "DEBUG"; }
log.info() { log "${1}" "INFO"; }
log.warn() { log "${1}" "WARN"; }
log.error() { log "${1}" "ERROR"; }
log.fatal() { log "${1}" "FATAL"; }

log.debug.show_vars() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
    local script_vars
    echo
    log.debug "=== Environment variables ==="
    readarray -t script_vars < <(compgen -A variable | grep "DAOS_\|AZ_" | sort)
    for script_var in "${script_vars[@]}"; do
      log.debug "${script_var}=${!script_var}"
    done
    echo
  fi
}
# END: Logging variables and functions

# Load environment variables from the file specified in BUILD_ENV_FILE if it
# has been set. This allows for different image build configurations to be
# stored in files outside of the repo so that custom images can be built for
# testing.
BUILD_ENV_FILE="${1:-}"
if [[ -n $BUILD_ENV_FILE ]]; then
  if [[ -f "${BUILD_ENV_FILE}" ]]; then
    echo "Sourcing ${BUILD_ENV_FILE}"
    source "${BUILD_ENV_FILE}"
  else
    echo "ERROR File not found: ${BUILD_ENV_FILE}"
    exit 1
  fi
fi

# Variables that can be overidden
DAOS_INSTALL_FROM_SOURCE="${DAOS_INSTALL_FROM_SOURCE:="true"}"
DAOS_VERSION="${DAOS_VERSION:="2.2.0"}"
DAOS_REPO_BASE_URL="${DAOS_REPO_BASE_URL:="https://packages.daos.io"}"
DAOS_PACKAGES_REPO_FILE="${DAOS_PACKAGES_REPO_FILE:="EL8/packages/x86_64/daos_packages.repo"}"
DAOS_INSTALL_TYPE="${DAOS_INSTALL_TYPE:="server"}"
DAOS_GIT_REPO_URL="${DAOS_GIT_REPO_URL:="https://github.com/daos-stack/daos.git"}"
DAOS_GIT_REPO_BRANCH="${DAOS_GIT_REPO_BRANCH:="release/2.4"}"
DAOS_GIT_REPO_TAG="${DAOS_GIT_REPO_TAG:=""}"
DAOS_UTILS_SCRIPT="${DAOS_UTILS_SCRIPT:="utils/scripts/install-el8.sh"}"
DAOS_APPLY_PATCHES="${DAOS_APPLY_PATCHES:=true}"
DAOS_IMAGE_NAME_PREFIX="${DAOS_IMAGE_NAME_PREFIX:="azure-daos-alma8"}"
DAOS_PACKER_TEMPLATE="${DAOS_PACKER_TEMPLATE:="daos_from_source.pkr.hcl"}"
DAOS_ANSIBLE_PLAYBOOK="${DAOS_ANSIBLE_PLAYBOOK:="install_daos_from_source.yml"}"
DAOS_NR_HUGEPAGES="${DAOS_NR_HUGEPAGES:=8096}"
AZ_SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:=$(az account show --query 'id' -o tsv)}"
AZ_RESOURCE_GROUP="${AZ_RESOURCE_GROUP:=$(az configure --list-defaults -o jsonc | jq -r '.[] | select(.name == "group") | .value')}"
AZ_LOCATION="${AZ_LOCATION:=$(az group show --name "${AZ_RESOURCE_GROUP}" --query 'location' -o tsv)}"
AZ_IMAGE_OFFER="${AZ_IMAGE_OFFER:="almalinux"}"
AZ_IMAGE_PUBLISHER="${AZ_IMAGE_PUBLISHER:="almalinux"}"
AZ_IMAGE_SKU="${AZ_IMAGE_SKU:="8-gen2"}"
AZ_IMAGE_VERSION="${AZ_IMAGE_VERSION:="$(az vm image list --publisher almalinux --sku 8-gen2 --all | tail -n 1 | awk '{print $6}')"}"

DAOS_PACKER_TEMPLATE_PATH="${SCRIPT_DIR}/${DAOS_PACKER_TEMPLATE}"
DAOS_PACKER_VARS_FILE_PATH="${SCRIPT_DIR}/${DAOS_PACKER_TEMPLATE%.*}vars.hcl"
DAOS_PACKER_VARS_ENVTPL_FILE_PATH="${SCRIPT_DIR}/${DAOS_PACKER_TEMPLATE%.*}vars.hcl.envtpl"

cleanup() {
  local show_images=${1:-0}
  log.info "Running cleanup ..."
  if [[ -f "${DAOS_PACKER_VARS_FILE_PATH}" ]]; then
    rm -f "${DAOS_PACKER_VARS_FILE_PATH}"
  fi
  if [ "$show_images" -eq 1 ]; then
    log.info "List Image(s)"
    az image list
  fi
}

error_handler() {
  log.error "Script error occurred! Exiting ..."
  cleanup
  exit 1
}

create_packer_vars_file() {

  readarray -t daos_vars < <(compgen -A variable | grep "DAOS_\|AZ_" | sort)
  for var in "${daos_vars[@]}"; do
    export "$var"
  done

  log.info "Creating pkrvars file: ${DAOS_PACKER_VARS_FILE_PATH}"
  envsubst <"${DAOS_PACKER_VARS_ENVTPL_FILE_PATH}" >"${DAOS_PACKER_VARS_FILE_PATH}"
}

run_packer() {
  [[ "${LOG_LEVEL}" == "DEBUG" ]] && PACKER_LOG=1
  log.info "Running packer to build image"
  packer init -var-file="${DAOS_PACKER_VARS_FILE_PATH}" "${DAOS_PACKER_TEMPLATE_PATH}"
  packer build -var-file="${DAOS_PACKER_VARS_FILE_PATH}" "${DAOS_PACKER_TEMPLATE_PATH}"
}

main() {
  log.debug.show_vars
  create_packer_vars_file
  run_packer
  cleanup 1
}

main
