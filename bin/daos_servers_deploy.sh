#!/usr/bin/env bash

set -eo pipefail

trap 'echo "daos_servers_deploy.sh : Unexpected error. Exiting.' ERR

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
. "${SCRIPT_DIR}/_log.sh"

SCRIPT_ENV_FILE="${DAOS_SERVERS_DEPLOY_ENV_FILE:="${SCRIPT_FILE%.*}.env"}"
if [[ -f "${SCRIPT_ENV_FILE}" ]]; then
  log.info "${SCRIPT_ENV_FILE} exists. Loading environment variables from the file."
  . "${SCRIPT_ENV_FILE}"
fi

ARM_DIR="$(realpath ${SCRIPT_DIR}/../arm/daos)"
VM_FILES_DIR="$(realpath "${SCRIPT_DIR}/../vm_files/daos_server")"

DAOS_AZ_RESOURCE_PREFIX="${DAOS_AZ_RESOURCE_PREFIX:="${USER}"}"
DAOS_AZ_RG_DEPLOYMENT_NAME="${DAOS_AZ_RG_DEPLOYMENT_NAME:="${DAOS_AZ_RESOURCE_PREFIX}-daos-cluster"}"
DAOS_AZ_RG_NAME="${DAOS_AZ_RG_NAME:="$(az config get defaults.group -o tsv --only-show-errors | awk '{print $3}')"}"
DAOS_AZ_ARM_SRC_TEMPLATE="${DAOS_AZ_ARM_SRC_TEMPLATE:="azuredeploy_server_template.json"}"
DAOS_AZ_ARM_DEST_TEMPLATE="${DAOS_AZ_ARM_DEST_TEMPLATE:="azuredeploy_server.json"}"
DAOS_AZ_IMAGE_PREFIX="${DAOS_AZ_IMAGE_PREFIX:="azure-daos-alma8"}"
DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_FILE="${DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_FILE:="${HOME}/.ssh/id_rsa.pub"}"
DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_DATA="${DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_DATA:="$(cat "${DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_FILE}")"}"
DAOS_VM_BASE_NAME="${DAOS_VM_BASE_NAME:="${DAOS_AZ_RESOURCE_PREFIX}-daos-server"}"
DAOS_AZ_SERVERS_GEN_ARM_ENV_FILE="${DAOS_AZ_SERVERS_GEN_ARM_ENV_FILE:="${SCRIPT_DIR}/daos_servers_gen_arm.env"}"

# Arm Template Parameter Values
DAOS_AZ_resourcePrefix="${DAOS_AZ_resourcePrefix:="${DAOS_AZ_RESOURCE_PREFIX}"}"
DAOS_AZ_existingVnetResourceGroupName="${DAOS_AZ_existingVnetResourceGroupName:="${DAOS_AZ_RG_NAME}"}"
DAOS_AZ_existingVnetName="${DAOS_AZ_existingVnetName:="${DAOS_AZ_resourcePrefix}-vnet"}"
DAOS_AZ_existingSubnetName="${DAOS_AZ_existingSubnetName:="${DAOS_AZ_resourcePrefix}-sn"}"
DAOS_AZ_daosAdminSku="${DAOS_AZ_daosAdminSku:="Standard_L8s_v3"}"
DAOS_AZ_daosAdminImageName="${DAOS_AZ_daosAdminImageName:=$(az image list -g "${DAOS_AZ_RG_NAME}" -o tsv | grep "${DAOS_AZ_IMAGE_PREFIX}" | awk '{print $5}' | sort | tail -1)}"
DAOS_AZ_daosServerImageName="${DAOS_AZ_daosServerImageName:="${DAOS_AZ_daosAdminImageName}"}"
DAOS_AZ_daosServerSku="${DAOS_AZ_daosServerSku:="Standard_L8s_v3"}"
DAOS_AZ_adminUser="${DAOS_AZ_adminUser:="daos_admin"}"
DAOS_AZ_serverCount="${DAOS_AZ_serverCount:=3}"
DAOS_AZ_serverNumDisks="${DAOS_AZ_serverNumDisks:=8}"
DAOS_AZ_serverDiskSize="${DAOS_AZ_serverDiskSize:=512}"
DAOS_AZ_serverStorageSku="${DAOS_AZ_serverStorageSku:="Premium_LRS"}"
DAOS_AZ_useAvailabilityZone="${DAOS_AZ_useAvailabilityZone:=true}"
DAOS_AZ_availabilityZone="${DAOS_AZ_availabilityZone:=1}"

readarray -t daos_vars < <(compgen -A variable | grep "DAOS" | sort)
for var in "${daos_vars[@]}"; do
  export "$var"
  log.debug "Exported: $var"
done

log.info "Generating file: ${DAOS_AZ_SERVERS_GEN_ARM_ENV_FILE}"
cat >"${DAOS_AZ_SERVERS_GEN_ARM_ENV_FILE}" <<EOF
DAOS_AZ_RG_NAME="${DAOS_AZ_RG_NAME}"
DAOS_VM_COUNT=${DAOS_AZ_serverCount}
DAOS_AZ_RESOURCE_PREFIX="${DAOS_AZ_RESOURCE_PREFIX:="${USER}"}"
DAOS_AZ_ARM_SRC_TEMPLATE="${DAOS_AZ_ARM_SRC_TEMPLATE:="azuredeploy_server_template.json"}"
DAOS_AZ_ARM_DEST_TEMPLATE="${DAOS_AZ_ARM_DEST_TEMPLATE:="azuredeploy_server.json"}"
DAOS_VM_FILES_DIR="${DAOS_VM_FILES_DIR:="${VM_FILES_DIR}"}"
DAOS_VM_ENTRY_SCRIPT="${DAOS_VM_ENTRY_SCRIPT:="daos_server_setup.sh"}"
DAOS_VM_BASE_NAME="${DAOS_VM_BASE_NAME:="${DAOS_AZ_RESOURCE_PREFIX}-daos-server"}"
DAOS_AZ_serverCount="${DAOS_AZ_serverCount:=1}"
EOF

log.info "Running ${SCRIPT_DIR}/daos_servers_gen_arm.sh"
"${SCRIPT_DIR}/daos_servers_gen_arm.sh"

log.info "Creating group deployment: ${DAOS_AZ_RG_DEPLOYMENT_NAME}"
az deployment group create \
  --resource-group "${DAOS_AZ_RG_NAME}" \
  --name "${DAOS_AZ_RG_DEPLOYMENT_NAME}" \
  --template-file "${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}" \
  --parameters resourcePrefix="${DAOS_AZ_resourcePrefix}" \
  --parameters existingVnetResourceGroupName="${DAOS_AZ_existingVnetResourceGroupName}" \
  --parameters existingVnetName="${DAOS_AZ_existingVnetName=}" \
  --parameters existingSubnetName="${DAOS_AZ_existingSubnetName}" \
  --parameters daosAdminSku="${DAOS_AZ_daosAdminSku}" \
  --parameters daosAdminImageName="${DAOS_AZ_daosAdminImageName}" \
  --parameters daosServerImageName="${DAOS_AZ_daosServerImageName}" \
  --parameters daosServerSku="${DAOS_AZ_daosServerSku}" \
  --parameters adminUser="${DAOS_AZ_adminUser}" \
  --parameters adminRsaPublicKey="${DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_DATA}" \
  --parameters serverCount="${DAOS_AZ_serverCount}" \
  --parameters serverNumDisks="${DAOS_AZ_serverNumDisks}" \
  --parameters serverDiskSize="${DAOS_AZ_serverDiskSize}" \
  --parameters serverStorageSku="${DAOS_AZ_serverStorageSku}" \
  --parameters useAvailabilityZone="${DAOS_AZ_useAvailabilityZone}" \
  --parameters availabilityZone="${DAOS_AZ_availabilityZone}"

if [[ -f "${DAOS_AZ_SERVERS_GEN_ARM_ENV_FILE}" ]]; then
  rm -f "${DAOS_AZ_SERVERS_GEN_ARM_ENV_FILE}"
fi

if [[ -f "${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}" ]]; then
  rm -f "${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}"
fi
