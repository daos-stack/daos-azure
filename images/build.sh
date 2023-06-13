#!/usr/bin/env bash
# shellcheck disable=SC2155
# shellcheck disable=SC1090

set -euo pipefail

trap 'error_handler' ERR SIGINT

DEFAULT_DAOS_VERSION="2.2.0"
DEFAULT_DAOS_REPO_BASE_URL="https://packages.daos.io"
DEFAULT_DAOS_PACKAGES_REPO_FILE="EL8/packages/x86_64/daos_packages.repo"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

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

export DAOS_INSTALL_FROM_SOURCE="${DAOS_INSTALL_FROM_SOURCE:="true"}"
export DAOS_VERSION="${DAOS_VERSION:="${DEFAULT_DAOS_VERSION}"}"
export DAOS_REPO_BASE_URL="${DAOS_REPO_BASE_URL:="${DEFAULT_DAOS_REPO_BASE_URL}"}"
export DAOS_PACKAGES_REPO_FILE="${DAOS_PACKAGES_REPO_FILE:="${DEFAULT_DAOS_PACKAGES_REPO_FILE}"}"
export DAOS_INSTALL_TYPE="${DAOS_INSTALL_TYPE:="server"}"
export DAOS_GIT_REPO_URL="${DAOS_GIT_REPO_URL:="https://github.com/daos-stack/daos.git"}"
export DAOS_GIT_REPO_BRANCH="${DAOS_GIT_REPO_BRANCH:="master"}"
export DAOS_GIT_REPO_TAG="${DAOS_GIT_REPO_TAG:="v2.3.108-tb"}"
export DAOS_UTILS_SCRIPT="${DAOS_UTILS_SCRIPT:="utils/scripts/install-el8.sh"}"
export DAOS_APPLY_PATCHES="${DAOS_APPLY_PATCHES:=true}"
export DAOS_IMAGE_NAME_PREFIX="${DAOS_IMAGE_NAME_PREFIX:="azure-daos-alma8"}"
export DAOS_PACKER_TEMPLATE="${DAOS_PACKER_TEMPLATE:="daos_from_source.pkr.hcl"}"
export DAOS_PACKER_VARS_FILE="${DAOS_PACKER_VARS_FILE:=}"
export DAOS_ANSIBLE_PLAYBOOK="${DAOS_ANSIBLE_PLAYBOOK:="install_daos_from_source.yml"}"
export DAOS_NR_HUGEPAGES="${DAOS_NR_HUGEPAGES:=8096}"
export AZ_SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
export AZ_RESOURCE_GROUP="$(az configure --list-defaults -o jsonc | jq -r '.[] | select(.name == "group") | .value')"
export AZ_LOCATION="$(az group show --name "${AZ_RESOURCE_GROUP}" --query 'location' -o tsv)"
export AZ_IMAGE_OFFER="${AZ_IMAGE_OFFER:="almalinux"}"
export AZ_IMAGE_PUBLISHER="${AZ_IMAGE_PUBLISHER:="almalinux"}"
export AZ_IMAGE_SKU="${AZ_IMAGE_SKU:="8-gen2"}"
export AZ_IMAGE_VERSION="${AZ_IMAGE_VERSION:="8.7.2022122801"}"

DAOS_PACKER_TEMPLATE_PATH="${SCRIPT_DIR}/${DAOS_PACKER_TEMPLATE}"

set +u
if [[ -z $DAOS_PACKER_VARS_FILE ]]; then
  DAOS_PACKER_VARS_FILE_PATH="${SCRIPT_DIR}/${DAOS_PACKER_TEMPLATE%.*}vars.hcl"
else
  DAOS_PACKER_VARS_FILE_PATH="${DAOS_PACKER_VARS_FILE}"
fi
set -u

DAOS_PACKER_VARS_FILE_TPL="${SCRIPT_DIR}/${DAOS_PACKER_TEMPLATE%.*}vars.hcl.envtpl"

cleanup() {
  local show_images=${1:-0}
  echo "Running cleanup ..."
  if [[ -f "${DAOS_PACKER_VARS_FILE_PATH}" ]]; then
    rm -f "${DAOS_PACKER_VARS_FILE_PATH}"
  fi
  if [ "$show_images" -eq 1 ]; then
    printf "\n\nImage(s)\n\n"
    az image list
  fi
}

error_handler() {
  echo "Script error occurred! Exiting ..."
  cleanup
  exit 1
}

# Create pkrvars file
envsubst <"${DAOS_PACKER_VARS_FILE_TPL}" >"${DAOS_PACKER_VARS_FILE_PATH}"

packer init -var-file="${DAOS_PACKER_VARS_FILE_PATH}" "${DAOS_PACKER_TEMPLATE_PATH}"
packer build -var-file="${DAOS_PACKER_VARS_FILE_PATH}" "${DAOS_PACKER_TEMPLATE_PATH}"

cleanup 1
