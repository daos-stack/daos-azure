#!/usr/bin/env bash

set -eo pipefail

trap 'echo "${BASH_SOURCE[0]} : Unexpected error. Exiting."' ERR

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")

DEFAULT_ENV_FILE="${SCRIPT_DIR}/../daos-azure.env"
DAOS_AZ_ENV_FILE="${DAOS_AZ_ENV_FILE:="${DEFAULT_ENV_FILE}"}"

ARM_DIR="$(realpath "${SCRIPT_DIR}/../arm/daos")"
VM_FILES_DIR="$(realpath "${SCRIPT_DIR}/../vm_files/daos_server")"

# Logging functions
source "${SCRIPT_DIR}/_log.sh"

source_build_env_file() {
  local env_file="${1}"
  if [[ -n "${env_file}" ]]; then
    if [[ -f "${env_file}" ]]; then
      log.debug "Sourcing ${env_file}"
      source "${env_file}"
      log.debug.vars
    else
      log.error "ERROR File not found: ${env_file}"
      exit 1
    fi
  else
    log.debug "Checking for existence of ${DAOS_AZ_ENV_FILE}"
    if [[ -f "${DAOS_AZ_ENV_FILE}" ]]; then
      log.debug "Sourcing ${DAOS_AZ_ENV_FILE}"
      source "${DAOS_AZ_ENV_FILE}"
    else
      log.error "File not found: ${DAOS_AZ_ENV_FILE}"
      exit 1
    fi
  fi
}

export_vars() {
  readarray -t pkr_vars < <(compgen -A variable | grep "DAOS_" | sort)
  for var in "${pkr_vars[@]}"; do
    export "$var"
  done
}

set_vars() {
  local res_prefix="daos"

  log.debug "Setting variables"

  if [[ -n "${DAOS_AZ_CORE_RESOURCE_PREFIX}" ]]; then
    res_prefix="${DAOS_AZ_CORE_RESOURCE_PREFIX}-daos"
  fi

  DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME="${DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME:="${res_prefix}-server-deployment"}"
  DAOS_AZ_ARM_SVR_SRC_TEMPLATE="${DAOS_AZ_ARM_SRC_TEMPLATE:="azuredeploy_server_template.json"}"
  DAOS_AZ_ARM_SVR_DEST_TEMPLATE="${DAOS_AZ_ARM_DEST_TEMPLATE:="azuredeploy_server.json"}"
  DAOS_AZ_ARM_SVR_VMSS_NAME="${DAOS_AZ_ARM_SVR_VMSS_NAME:="${res_prefix}-server-vmss"}"
  DAOS_AZ_SSH_ADMIN_KEY_PUB_DATA="${DAOS_AZ_SSH_ADMIN_KEY_PUB_DATA:="$(cat "${DAOS_AZ_SSH_ADMIN_KEY_PUB}")"}"
  export_vars
  log.debug.vars
}

generate_arm_template() {
  # Generate a set of files that will be included in self a extracting
  # executable file that will be run by cloud-init on the DAOS Server VMs
  log.info "Running ${SCRIPT_DIR}/daos_servers_gen_arm.sh"
  "${SCRIPT_DIR}/daos_servers_gen_arm.sh"
}

deploy() {
  log.info "Creating group deployment: ${DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME}"
  az deployment group create \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --name "${DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME}" \
    --template-file "${ARM_DIR}/${DAOS_AZ_ARM_SVR_DEST_TEMPLATE}" \
    --parameters resourcePrefix="${DAOS_AZ_CORE_RESOURCE_PREFIX}" \
    --parameters existingVnetResourceGroupName="${DAOS_AZ_CORE_RG_NAME}" \
    --parameters existingVnetName="${DAOS_AZ_NET_VNET_NAME}" \
    --parameters existingSubnetName="${DAOS_AZ_NET_SUBNET_NAME}" \
    --parameters daosServerImageId="${DAOS_AZ_ARM_SVR_IMG_ID}" \
    --parameters daosServerSku="${DAOS_AZ_ARM_SVR_SKU}" \
    --parameters adminUser="${DAOS_AZ_ARM_ADMIN_USER}" \
    --parameters adminRsaPublicKey="${DAOS_AZ_SSH_ADMIN_KEY_PUB_DATA}" \
    --parameters vmScalesetName="${DAOS_AZ_ARM_SVR_VMSS_NAME}" \
    --parameters serverCount="${DAOS_AZ_ARM_SVR_COUNT}" \
    --parameters serverDiskCount="${DAOS_AZ_ARM_SVR_DISK_COUNT}" \
    --parameters serverDiskSize="${DAOS_AZ_ARM_SVR_DISK_SIZE}" \
    --parameters serverStorageSku="${DAOS_AZ_ARM_SVR_DISK_STORAGE_SKU}" \
    --parameters useAvailabilityZone="${DAOS_AZ_ARM_SVR_USE_AVAIL_ZONE}" \
    --parameters availabilityZone="${DAOS_AZ_ARM_SVR_AVAIL_ZONE}" \
    --parameters userAssignedManagedIdentityName="${DAOS_AZ_ARM_UAMID_NAME}"

}

cleanup() {
  if [[ -f "${SCRIPT_DIR}/daos_servers_gen_arm.env" ]]; then
    rm -f "${SCRIPT_DIR}/daos_servers_gen_arm.env"
  fi

  if [[ -f "${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}" ]]; then
    rm -f "${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}"
  fi
}

main() {
  source_build_env_file "$@"
  set_vars
  generate_arm_template
  deploy
  cleanup
}

main "$@"
