#!/usr/bin/env bash

set -eo pipefail

#trap 'error_handler' ERR

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
ARM_DIR="$(realpath ${SCRIPT_DIR}/../arm/daos)"
VM_FILES_DIR="$(realpath "${SCRIPT_DIR}/../vm_files/daos_server")"

DAOS_AZ_RESOURCE_PREFIX="${USER}"
DAOS_AZ_RG_DEPLOYMENT_NAME="${DAOS_AZ_RESOURCE_PREFIX}-daos-cluster"
DAOS_AZ_RG_NAME="$(az config get defaults.group -o tsv --only-show-errors | awk '{print $3}')"
DAOS_AZ_ARM_SRC_TEMPLATE="azuredeploy_server_template.json"
DAOS_AZ_ARM_DEST_TEMPLATE="azuredeploy_server.json"
DAOS_AZ_IMAGE_PREFIX="azure-daos-alma8"
DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_DATA=$(cat "${DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_FILE}")
DAOS_VM_BASE_NAME="${DAOS_AZ_RESOURCE_PREFIX}-daos-server"
DAOS_SCM_SIZE=40

# Arm Template Parameter Values
DAOS_AZ_resourcePrefix="${DAOS_AZ_RESOURCE_PREFIX}"
DAOS_AZ_existingVnetResourceGroupName="${DAOS_AZ_RG_NAME}"
DAOS_AZ_existingVnetName="${DAOS_AZ_resourcePrefix}-vnet"
DAOS_AZ_existingSubnetName="${DAOS_AZ_resourcePrefix}-sn"
DAOS_AZ_daosAdminSku="Standard_L8s_v3"
DAOS_AZ_daosAdminImageName=$(az image list -g "${DAOS_AZ_RG_NAME}" -o tsv | grep "${DAOS_AZ_IMAGE_FAMILY}" | awk '{print $5}' | sort | tail -1)
DAOS_AZ_daosServerImageName="${DAOS_AZ_daosAdminImageName}"
DAOS_AZ_daosServerSku="Standard_L8s_v3"
DAOS_AZ_adminUser="daos_admin"
DAOS_AZ_serverCount=3
DAOS_AZ_serverNumDisks=8
DAOS_AZ_serverDiskSize=512
DAOS_AZ_serverStorageSku="Premium_LRS"
DAOS_AZ_useAvailabilityZone=true
DAOS_AZ_availabilityZone=1

# BEGIN: Logging variables and functions
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [FATAL]=4 [OFF]=5)
declare -A LOG_COLORS=([DEBUG]=2 [INFO]=12 [WARN]=3 [ERROR]=1 [FATAL]=9 [OFF]=0 [OTHER]=15)
LOG_LEVEL=DEBUG

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
log.vars() {
  local daos_vars
  if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
    log.debug && log.debug "ENVIRONMENT VARIABLES" && log.debug "---"
    readarray -t daos_vars < <(compgen -A variable | grep "DAOS" | sort)
    for item in "${daos_vars[@]}"; do
      log.debug "${item}=${!item}"
    done
    log.debug "---"
  fi
}
# END: Logging variables and functions

readarray -t daos_vars < <(compgen -A variable | grep "DAOS" | sort)
for var in "${daos_vars[@]}"; do
  export "$var"
  log.debug "Exported: $var"
done

cat >"${SCRIPT_DIR}/daos_servers_gen_arm.env" <<EOF
DAOS_AZ_RG_NAME="${DAOS_AZ_RG_NAME}"
DAOS_VM_COUNT=${DAOS_AZ_serverCount}
DAOS_SCM_SIZE=40
DAOS_AZ_RESOURCE_PREFIX="${DAOS_AZ_RESOURCE_PREFIX:="${USER}"}"
DAOS_AZ_ARM_SRC_TEMPLATE="${DAOS_AZ_ARM_SRC_TEMPLATE:="azuredeploy_server_template.json"}"
DAOS_AZ_ARM_DEST_TEMPLATE="${DAOS_AZ_ARM_DEST_TEMPLATE:="azuredeploy_server.json"}"
DAOS_VM_FILES_DIR="${DAOS_VM_FILES_DIR:="${VM_FILES_DIR}"}"
DAOS_VM_ENTRY_SCRIPT="${DAOS_VM_ENTRY_SCRIPT:="daos_server_setup.sh"}"
DAOS_VM_BASE_NAME="${DAOS_VM_BASE_NAME:="${DAOS_AZ_RESOURCE_PREFIX}-daos-server"}"
DAOS_AZ_serverCount="${DAOS_AZ_serverCount:=1}"
EOF

"${SCRIPT_DIR}/daos_servers_gen_arm.sh"

log.debug "az deployment group create \\
  --resource-group \"${DAOS_AZ_RG_NAME}\" \\
  --name \"${DAOS_AZ_RG_DEPLOYMENT_NAME}\" \\
  --template-file \"${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}\" \\
  --parameters resourcePrefix=\"${DAOS_AZ_resourcePrefix}\" \\
  --parameters existingVnetResourceGroupName=\"${DAOS_AZ_existingVnetResourceGroupName}\" \\
  --parameters existingVnetName=\"${DAOS_AZ_existingVnetName=}\" \\
  --parameters existingSubnetName=\"${DAOS_AZ_existingSubnetName}\" \\
  --parameters daosAdminSku=\"${DAOS_AZ_daosAdminSku}\" \\
  --parameters daosAdminImageName=\"${DAOS_AZ_daosAdminImageName}\" \\
  --parameters daosServerImageName=\"${DAOS_AZ_daosServerImageName}\" \\
  --parameters daosServerSku=\"${DAOS_AZ_daosServerSku}\" \\
  --parameters adminUser=\"${DAOS_AZ_adminUser}\" \\
  --parameters adminRsaPublicKey=\"${DAOS_AZ_ADMIN_RSA_PUBLIC_KEY_DATA}\" \\
  --parameters serverCount=\"${DAOS_AZ_serverCount}\" \\
  --parameters serverNumDisks=\"${DAOS_AZ_serverNumDisks}\" \\
  --parameters serverDiskSize=\"${DAOS_AZ_serverDiskSize}\" \\
  --parameters serverStorageSku=\"${DAOS_AZ_serverStorageSku}\" \\
  --parameters useAvailabilityZone=\"${DAOS_AZ_useAvailabilityZone}\" \\
  --parameters availabilityZone=\"${DAOS_AZ_availabilityZone}\" "

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

if [[ -f "${SCRIPT_DIR}/daos_servers_gen_arm.env" ]]; then
  rm -f "${SCRIPT_DIR}/daos_servers_gen_arm.env"
fi

if [[ -f "${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}" ]]; then
  rm -f "${ARM_DIR}/${DAOS_AZ_ARM_DEST_TEMPLATE}"
fi
