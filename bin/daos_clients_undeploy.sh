#!/usr/bin/env bash

set -eo pipefail

trap 'echo "daos_clients_undeploy.sh : Unexpected error. Exiting.' ERR

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
. "${SCRIPT_DIR}/_log.sh"

SCRIPT_ENV_FILE="${DAOS_CLIENTS_UNDEPLOY_ENV_FILE:="${SCRIPT_FILE%.*}.env"}"
if [[ -f "${SCRIPT_ENV_FILE}" ]]; then
  log.info "${SCRIPT_ENV_FILE} exists. Loading environment variables from the file."
  . "${SCRIPT_ENV_FILE}"
fi

DAOS_AZ_RESOURCE_PREFIX="${DAOS_AZ_RESOURCE_PREFIX:="${USER}"}"
DAOS_AZ_RG_DEPLOYMENT_NAME="${DAOS_AZ_RG_DEPLOYMENT_NAME:="${DAOS_AZ_RESOURCE_PREFIX}-daos-clients"}"
DAOS_AZ_RG_NAME="${DAOS_AZ_RG_NAME:="$(az config get defaults.group -o tsv --only-show-errors | awk '{print $3}')"}"

log.debug.vars "DAOS"

log.info "Deployment '${DAOS_AZ_RG_DEPLOYMENT_NAME}'"
az deployment group show \
  -g "${DAOS_AZ_RG_NAME}" \
  -n "${DAOS_AZ_RG_DEPLOYMENT_NAME}"

log.info "Deleting resources"
for i in $(az deployment group show \
  -g "${DAOS_AZ_RG_NAME}" \
  -n "${DAOS_AZ_RG_DEPLOYMENT_NAME}" \
  --query "properties.outputs.resourceIds.value[]" \
  -o tsv); do

  log.info "Deleting Resource: ${i}"
  az resource delete --ids "${i}"
done

log.info "Deleting Deployment: ${DAOS_AZ_RG_DEPLOYMENT_NAME}"
az deployment group delete -g "${DAOS_AZ_RG_NAME}" -n "${DAOS_AZ_RG_DEPLOYMENT_NAME}"
