#!/usr/bin/env bash

DAOS_AZ_RESOURCE_PREFIX="${USER}"
DAOS_AZ_RG_DEPLOYMENT_NAME="${DAOS_AZ_RESOURCE_PREFIX}-daos-clients"
DAOS_AZ_RG_NAME="$(az config get defaults.group -o tsv --only-show-errors | awk '{print $3}')"
# DAOS_AZ_ARM_SRC_TEMPLATE="azuredeploy_client_template.json"
# DAOS_AZ_ARM_DEST_TEMPLATE="azuredeploy_client.json"
# DAOS_AZ_IMAGE_PREFIX="azure-daos-alma8"
# DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
# DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_DATA=$(cat "${DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_FILE}")
# DAOS_VM_BASE_NAME="${DAOS_AZ_RESOURCE_PREFIX}-daos-client"

#az group deployment show --name "${DAOS_AZ_RG_DEPLOYMENT_NAME}" --resource-group maolson-rg --query properties.outputs
echo
echo "-------------------------------------------------------------------------"
echo "Undeploying '${DAOS_AZ_RG_DEPLOYMENT_NAME}'"
echo "-------------------------------------------------------------------------"
echo
echo "DEPLOYMENT:"
az deployment group show -g "maolson-rg" -n "maolson-daos-clients" -o tsv

az deployment group show \
  -g "${DAOS_AZ_RG_NAME}" \
  -n "${DAOS_AZ_RG_DEPLOYMENT_NAME}"

echo
echo "OUTPUTS:"
for i in $(az deployment group show \
  -g "${DAOS_AZ_RG_NAME}" \
  -n "${DAOS_AZ_RG_DEPLOYMENT_NAME}" \
  --query "properties.outputs.resourceIds.value[]" \
  -o tsv); do

  echo "Deleting Resource: ${i}"
  az resource delete --ids "${i}"
done

echo
echo "Deleting Deployment: ${DAOS_AZ_RG_DEPLOYMENT_NAME}"
az deployment group delete -g "${DAOS_AZ_RG_NAME}" -n "${DAOS_AZ_RG_DEPLOYMENT_NAME}"
