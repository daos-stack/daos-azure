#!/usr/bin/env bash
# Copyright (c) 2023 Intel Corporation All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -eo pipefail

trap 'echo "${BASH_SOURCE[0]} : Unexpected error. Exiting."' ERR

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../daos-azure.env"
DAOS_AZ_ENV_FILE="${DAOS_AZ_ENV_FILE:="${DEFAULT_ENV_FILE}"}"
ARM_DIR="${SCRIPT_DIR}/../arm/daos"
BICEP_DIR="$(realpath "${SCRIPT_DIR}/../bicep")"
ACTION="help"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_log.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_inc.sh"

show_help() {

  echo "

Manage DAOS server deployment

Usage:

  ${SCRIPT_FILE} [<options>]

Options:

  [ -e | --env-file DAOS_AZ_ENV_FILE ]  Use specified environment file.
                                        By default the bin/../daos-azure.env
                                        file will be sourced if it exists.

  [ -d | --deploy ]                     Deploy DAOS server VM Scale Set
  [ -u | --undeploy ]                   Undeploy DAOS server VM Scale Set
  [ -g | --gen-arm ]                    Generate ARM templates only. Do not deploy.
  [ --no-clean ]                        Do not delete temporary files used to create cloud-int
  [ -h | --help ]                       Show this help

"

}

load_env() {
  inc.env_load "$(realpath "${DAOS_AZ_ENV_FILE}")"
  DAOS_AZ_CLOUD_INIT_CLEANUP="${DAOS_AZ_CLOUD_INIT_CLEANUP:=true}"
  #shellcheck disable=SC2162,SC2034
  DAOS_AZ_SSH_ADMIN_KEY_PUB_DATA="$(cat "${DAOS_AZ_SSH_ADMIN_KEY_PUB}")"
  inc.env_export
  log.debug.vars
}

generate_arm() {
  mkdir -p "${ARM_DIR}"

  local extra_args
  if [[ "${DAOS_AZ_CLOUD_INIT_CLEANUP}" == "false" ]]; then
      extra_args="--no-clean"
  fi

  log.info "Generating cloud-init script"
  "${SCRIPT_DIR}/gen_cloudinit.sh" \
    --archive-dir "${SCRIPT_DIR}/../vm_files/daos_server" \
    --start-script "daos_server_setup.sh" \
    --target-dir "/root/daos_server_setup" \
    --out-file "${SCRIPT_DIR}/cloudinit_server.sh" \
    $extra_args

  log.info "Linting bicep file: ${BICEP_DIR}/daos_servers.bicep"
  bicep lint "${BICEP_DIR}/daos_servers.bicep"

  log.info "Generating ARM parameter file: ${ARM_DIR}/azuredeploy_server.params.json"
  bicep build-params "${BICEP_DIR}/daos_servers.bicepparam" \
    --outfile "${ARM_DIR}/azuredeploy_server.params.json"

  log.info "Generating ARM template file: ${ARM_DIR}/azuredeploy_server.json"
  bicep build "${BICEP_DIR}/daos_servers.bicep" \
    --outfile "${ARM_DIR}/azuredeploy_server.json"

  if [[ "${DAOS_AZ_CLOUD_INIT_CLEANUP}" == "true" ]]; then
    [[ -f "${SCRIPT_DIR}/cloudinit_server.sh" ]] && rm -f "${SCRIPT_DIR}/cloudinit_server.sh"
  fi
}

accept_img_terms() {
  local answer

  if [[ ! -f "${SCRIPT_DIR}/.almalinux_accepted" ]]; then
    log.info "Accept marketplace terms for image: ${DAOS_AZ_ARM_IMG_URN}"
    echo "You must accept the marketplace terms for the 'AlmaLinux' image."
    read -r -p "Do you want to continue? (y/n) " answer

    if [[ "${answer,,}" != "y" ]]; then
      echo "Marketplace terms for the AlmaLinux image not accepted."
      echo "Exiting ..."
      exit 1
    fi

    az vm image terms accept \
      --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
      --urn "${DAOS_AZ_ARM_IMG_URN}" \
      --output json

    touch "${SCRIPT_DIR}/.almalinux_accepted"
  fi
}

deploy() {
  log.info "Deploying DAOS servers"

  accept_img_terms
  generate_arm

  log.info "Creating group deployment: ${DAOS_AZ_ARM_SERVER_GROUP_DEPLOYMENT_NAME}"
  az deployment group create \
    --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --name "${DAOS_AZ_ARM_SERVER_GROUP_DEPLOYMENT_NAME}" \
    --template-file "${ARM_DIR}/azuredeploy_server.json" \
    --parameters "${ARM_DIR}/azuredeploy_server.params.json" \
    --output table
}

undeploy() {
  if ! az group deployment list \
    --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    -g "${DAOS_AZ_CORE_RG_NAME}" \
    --query '[].name' -o tsv \
    | grep -q "${DAOS_AZ_ARM_SERVER_GROUP_DEPLOYMENT_NAME}"
  then
    log.info "Deployment '${DAOS_AZ_ARM_SERVER_GROUP_DEPLOYMENT_NAME}' does not exist."
    exit 1
  fi

  log.info "Undeploying resources deployed by '${DAOS_AZ_ARM_SERVER_GROUP_DEPLOYMENT_NAME}' deployment"

  for i in $(az deployment group show \
    --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --name "${DAOS_AZ_ARM_SERVER_GROUP_DEPLOYMENT_NAME}" \
    --query "properties.outputs.resourceIds.value[]" \
    --output tsv | grep vmss); do

    log.info "Deleting Resource: ${i}"
    az resource delete --ids "${i}" -o tsv
  done

  log.info "Deleting Deployment: ${DAOS_AZ_ARM_SERVER_GROUP_DEPLOYMENT_NAME}"
  az group deployment delete \
    --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --name "${DAOS_AZ_ARM_SERVER_GROUP_DEPLOYMENT_NAME}" \
    --output tsv

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
    --deploy | -d)
      ACTION="deploy"
      shift
      ;;
    --undeploy | -u)
      ACTION="undeploy"
      shift
      ;;
    --gen-arm | -g)
      ACTION="gen"
      shift
      ;;
    --no-clean)
      DAOS_AZ_CLOUD_INIT_CLEANUP="false"
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
  load_env
  case "${ACTION}" in
    help)
      show_help
      exit 0
      ;;
    deploy)
      deploy
      ;;
    undeploy)
      undeploy
      ;;
    gen)
      generate_arm
      ;;
    *)
      return
      ;;
  esac
}

main "$@"
