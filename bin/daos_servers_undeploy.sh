#!/usr/bin/env bash

set -eo pipefail

trap 'echo "${BASH_SOURCE[0]} : Error occured. Exiting..."' ERR

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")

DEFAULT_ENV_FILE="${SCRIPT_DIR}/../daos-azure.env"
DAOS_AZ_ENV_FILE="${DAOS_AZ_ENV_FILE:="${DEFAULT_ENV_FILE}"}"

source "${DAOS_AZ_ENV_FILE}"
source "${SCRIPT_DIR}/_log.sh"

log.debug.vars

log.info "Deployment '${DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME}'"
az deployment group show \
  -g "${DAOS_AZ_CORE_RG_NAME}" \
  -n "${DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME}"
echo

for i in $(az deployment group show \
  -g "${DAOS_AZ_CORE_RG_NAME}" \
  -n "${DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME}" \
  --query "properties.outputs.resourceIds.value[]" \
  -o tsv); do

  log.info "Deleting Resource: ${i}"
  az resource delete --ids "${i}"
done

log.info "Deleting Deployment: ${DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME}"
az group deployment delete \
  -g "${DAOS_AZ_CORE_RG_NAME}" \
  -n "${DAOS_AZ_ARM_SVR_GROUP_DEPLOYMENT_NAME}"
