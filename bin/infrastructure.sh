#!/usr/bin/env bash
# Copyright (c) 2024 Intel Corporation All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -eo pipefail

trap 'echo "${BASH_SOURCE[0]} : Unexpected error. Exiting."' ERR

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SCRIPT_FILE="$(basename "${BASH_SOURCE[0]}")"
DEFAULT_ENV_FILE="$(realpath "${SCRIPT_DIR}/../daos-azure.env")"
DAOS_AZ_ENV_FILE="${DAOS_AZ_ENV_FILE:="${DEFAULT_ENV_FILE}"}"
BICEP_DIR="$(realpath "${SCRIPT_DIR}/../bicep")"
ACTION="help"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_log.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_inc.sh"

show_help() {

  echo "

Manage DAOS infrastructure deployment

Usage:

  ${SCRIPT_FILE} [<options>]

Options:

  [ -e | --env-file DAOS_AZ_ENV_FILE ]  Use specified environment file
  [ -l | --list ]                       List infrastructure resources
  [ -d | --deploy ]                     Deploy DAOS infrastructure resources
  [ -u | --undeploy ]                   Undeploy DAOS infrastructure resources
  [ -h | --help ]                       Show this help

"
}

list() {
  log.info "List of DAOS infrastructure resources"

  if az group list --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --query "[?name=='${DAOS_AZ_CORE_RG_NAME}' && location=='${DAOS_AZ_CORE_LOCATION}']" | grep -q "${DAOS_AZ_CORE_RG_NAME}"; then
    log.info "Resource group: ${DAOS_AZ_CORE_RG_NAME}"
    log.info "Resources:"
    az deployment group show \
      --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
      --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
      --name "${DAOS_AZ_ARM_INFRA_GROUP_DEPLOYMENT_NAME}" \
      --query 'properties.outputResources[].id' \
      --output tsv
  else
    log.error "Resource group '${DAOS_AZ_CORE_RG_NAME}' does not exist."
    exit 1
  fi
}

create_resource_group() {
  if az group list --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --query "[?name=='${DAOS_AZ_CORE_RG_NAME}' && location=='${DAOS_AZ_CORE_LOCATION}']" | grep -q "${DAOS_AZ_CORE_RG_NAME}"; then
    log.info "Resource group '${DAOS_AZ_CORE_RG_NAME}' already exists."
  else
    log.info "Creating resource group: ${DAOS_AZ_CORE_RG_NAME}"
    az group create --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
      --name "${DAOS_AZ_CORE_RG_NAME}" \
      --location "${DAOS_AZ_CORE_LOCATION}" \
      --tags "${DAOS_AZ_CORE_RG_TAGS}"
  fi
}

restore_deleted_key_vault() {
  log.info "Recovering key vault: ${DAOS_AZ_ARM_KEY_VAULT_NAME}"
  az keyvault recover \
  --name "${DAOS_AZ_ARM_KEY_VAULT_NAME}" \
  --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
  --location "${DAOS_AZ_CORE_LOCATION}"
}

check_key_vault() {
  if az keyvault list-deleted \
    --resource-type vault \
    --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --query "[].name" \
    --output tsv \
    | grep -q "${DAOS_AZ_ARM_KEY_VAULT_NAME}"; then

    log.warn "Key vault '${DAOS_AZ_ARM_KEY_VAULT_NAME}' exists in a deleted state. Cannot create a new key vault with that name."

    # Prompt to create a key vault with a new name
    # Azure Key Vault names:
    #   1. Must be between 3-24 alphanumeric characters
    #   2. Must begin with a letter
    #   3. Must end with a letter or digit
    #   4. Must not contain consecutive hyphens

    local default_key_vault_name
    default_key_vault_name="${DAOS_AZ_CORE_RESOURCE_PREFIX:+${DAOS_AZ_CORE_RESOURCE_PREFIX}}daos"

    local unique_string
    unique_string=$(uuidgen | tr '[:upper:]' '[:lower:]' | sed 's/-//g')

    local new_vault_name
    new_vault_name="$(echo "${unique_string}${default_key_vault_name}" | tr '[:upper:]' '[:lower:]' | sed 's/-//g')"

    while [ "${#new_vault_name}" -gt 22 ]; do
        new_vault_name="${new_vault_name:1}"
    done
    new_vault_name="d${new_vault_name}"

    while true; do
      local answer
      read -r -p "
Create a new vault with the name '${new_vault_name}'
This will update the DAOS_AZ_ARM_KEY_VAULT_NAME variable in
${DAOS_AZ_ENV_FILE}? (y/n) " answer
      echo
      [[ $answer == [yn] ]] && break
      log.error "Invalid input. Please enter either 'y' or 'n'."
    done

    log.debug "answer=$answer"

    [[ "${answer,,}" == "n" ]] && exit 1

    export DAOS_AZ_ARM_KEY_VAULT_NAME="${new_vault_name}"
    sed -i "s/^DAOS_AZ_ARM_KEY_VAULT_NAME=.*/DAOS_AZ_ARM_KEY_VAULT_NAME=\"${DAOS_AZ_ARM_KEY_VAULT_NAME}\"/g" "${DAOS_AZ_ENV_FILE}"
  fi
}

deploy() {
  log.section "DAOS Infrastructure Deployment"
  create_resource_group
  check_key_vault
  log.info "Creating deployment: ${DAOS_AZ_ARM_INFRA_GROUP_DEPLOYMENT_NAME}"
  log.info "Deployment can take as long as 20 minutes. Please wait for the process to finish."
  az deployment group create \
    --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --name "${DAOS_AZ_ARM_INFRA_GROUP_DEPLOYMENT_NAME}" \
    --mode "Incremental" \
    --template-file "${BICEP_DIR}/infrastructure.bicep" \
    --parameters "${BICEP_DIR}/infrastructure.bicepparam" \
    --output table
}

undeploy() {
  local answer
  log.info "Undeploying resources deployed by '${DAOS_AZ_ARM_INFRA_GROUP_DEPLOYMENT_NAME}' deployment"
  read -r -p "
  Resource group '${DAOS_AZ_CORE_RG_NAME}' will be deleted.
  All resources in the group including DAOS servers and clients will be deleted.
  Do you want to continue? (y/n) " answer
  echo
  if [[ "${answer,,}" != "y" ]]; then
    echo "Exiting ..."
    exit 1
  fi

  if az group list --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --query "[?name=='${DAOS_AZ_CORE_RG_NAME}' && location=='${DAOS_AZ_CORE_LOCATION}']" | grep -q "${DAOS_AZ_CORE_RG_NAME}"; then
    log.info "Deleting resource group: ${DAOS_AZ_CORE_RG_NAME}"
    az group delete --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
      --name "${DAOS_AZ_CORE_RG_NAME}" \
      --force-deletion-types "Microsoft.Compute/virtualMachineScaleSets" \
      --force-deletion-types "Microsoft.Compute/virtualMachines" \
      --yes \
      --output table
  else
    log.error "Resource group '${DAOS_AZ_CORE_RG_NAME}' does not exist."
    exit 1
  fi
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
    --env-file | -e)
      DAOS_AZ_ENV_FILE="$2"
      if [[ "${DAOS_AZ_ENV_FILE}" == -* ]] || [[ "${DAOS_AZ_ENV_FILE}" = "" ]] || [[ -z ${DAOS_AZ_ENV_FILE} ]]; then
        log.error "Missing DAOS_AZ_ENV_FILE value for -e|--env-file"
        exit 1
      fi
      shift 2
      ;;
    --list | -l)
      ACTION="list"
      break
      ;;
    --deploy | -d)
      ACTION="deploy"
      break
      ;;
    --undeploy | -u)
      ACTION="undeploy"
      break
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
      log.error "Unrecognized option '${1}'"
      shift
      break
      ;;
    esac
  done
  set -e
}

main() {
  opts "$@"
  inc.env_load "${DAOS_AZ_ENV_FILE}"
  inc.env_export
  log.debug.vars
  case "${ACTION}" in
    help)
      show_help
      exit 0
      ;;
    list)
      list
      ;;
    deploy)
      deploy
      ;;
    undeploy)
      undeploy
      ;;
  esac
}

main "$@"
