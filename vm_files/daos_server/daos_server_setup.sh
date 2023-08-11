#!/usr/bin/env bash

exec >/var/log/daos_server_setup.log
exec 2>&1

set -o pipefail

trap 'error_handler' ERR

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")

# BEGIN: Logging Functions
DAOS_AZ_LOG_LEVEL="DEBUG"

declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [FATAL]=4 [OFF]=5)
declare -A LOG_COLORS=([DEBUG]=2 [INFO]=12 [WARN]=3 [ERROR]=1 [FATAL]=9 [OFF]=0 [OTHER]=15)

log() {
  local msg="$1"
  local lvl=${2:-INFO}
  if [[ ${LOG_LEVELS[$DAOS_AZ_LOG_LEVEL]} -le ${LOG_LEVELS[$lvl]} ]]; then
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
log.debug.vars() {
  if [[ "${DAOS_AZ_LOG_LEVEL}" == "DEBUG" ]]; then
    local script_vars
    echo
    log.debug "=== Environment variables ==="
    readarray -t script_vars < <(compgen -A variable | grep "DAOS_" | sort)
    for script_var in "${script_vars[@]}"; do
      log.debug "${script_var}=${!script_var}"
    done
    echo
  fi
}
# END: Logging Functions

error_handler() {
  log.error "An unknown error occurred"
  log.error "Exiting ${SCRIPT_DIR}/${SCRIPT_FILE}"
  log.info "END: ${SCRIPT_DIR}/${SCRIPT_FILE}"
}

load_env() {
  env_file="${SCRIPT_DIR}/${SCRIPT_FILE%.*}.env"
  if [[ -f "${env_file}" ]]; then
    echo "Sourcing ${env_file}"
    source "${env_file}"
  else
    echo "ERROR: File not found: '${env_file}'. Exiting..."
    exit 1
  fi
  log.debug.vars
}

az_setup() {
  log.info "Authenticating Azure CLI with user assigned managed identity"
  az login --identity
  log.info "Setting Azure CLI default Resource Group to '${DAOS_AZ_CORE_RG_NAME}'"
  az configure --defaults group="${DAOS_AZ_CORE_RG_NAME}"
  log.info "Setting Azure CLI default Location to '${DAOS_AZ_CORE_LOCATION}'"
  az configure --defaults location="${DAOS_AZ_CORE_LOCATION}"
}

wait_for_vmss() {
  local timeout=300
  local elapsed=0
  local interval=3
  local status=""

  while true; do
    log.info "Checking status of '${DAOS_AZ_ARM_SVR_VMSS_NAME}' scale set"
    local vmss_status=$(az vmss show --name "${DAOS_AZ_ARM_SVR_VMSS_NAME}" --query "provisioningState" -o tsv)

    if [[ -z $vmss_status ]]; then
      log.info "ERROR: No status found for scaleset ${DAOS_AZ_ARM_SVR_VMSS_NAME}. Exiting"
      exit 1
    fi

    log.debug "vmss_status=${vmss_status}"

    if [[ "${vmss_status}" == "Succeeded" ]]; then
      log.info "VMSS provisioning succeeded!"
      break # Exit the loop
    fi

    elapsed=$((elapsed + interval))
    if [ ${elapsed} -ge ${timeout} ]; then
      log.info "Timeout of ${timeout} seconds reached"
      log.info "ERROR: Unable to determine state of VM Scale Set '${DAOS_AZ_ARM_SVR_VMSS_NAME}'. Exiting ..."
      exit 1
    fi
    sleep ${interval}
  done

  az vmss list-instances --name "${DAOS_AZ_ARM_SVR_VMSS_NAME}" --query "[].osProfile.computerName" -o tsv | sort >/tmp/daos_server_vmss_vms
  az vmss list-instances --name "${DAOS_AZ_ARM_SVR_VMSS_NAME}" --query "[0].osProfile.computerName" -o tsv >/tmp/daos_first_server_vm
}

kv_set_secret() {
  local secret_name="$1"
  local file_name="$2"

  #local existing_secret_name=$(az keyvault secret list --vault-name "${DAOS_AZ_ARM_KEY_VAULT_NAME}" --query "[?name=='${secret_name}'].name")
  # if [[ "${existing_secret_name}" == "${secret_name}" ]]; then
  #   log.warn "Certificate '${cert_name}' already exists in '${DAOS_AZ_ARM_KEY_VAULT_NAME}' vault. Removing it."
  #   az keyvault secret delete \
  #     --name "${existing_secret_name}" \
  #     --vault-name "${DAOS_AZ_ARM_KEY_VAULT_NAME}"
  # fi

  log.info "Setting secret '${secret_name}' in '${DAOS_AZ_ARM_KEY_VAULT_NAME}' key vault."
  az keyvault secret set \
    --name "${secret_name}" \
    --vault-name "${DAOS_AZ_ARM_KEY_VAULT_NAME}" \
    --value "$(cat "${file_name}")" >/dev/null
}

kv_get_secret() {
  local secret_name="$1"
  local file_name="$2"
  log.info "Get ${file_name} from '${DAOS_AZ_ARM_KEY_VAULT_NAME}' key vault"
  az keyvault secret show \
    --vault-name "${DAOS_AZ_ARM_KEY_VAULT_NAME}" \
    --name "${secret_name}" \
    --query "value" \
    -o tsv >"${file_name}"
}

is_first_server() {
  set +e
  if [[ "$(hostname -s)" == "$(cat /tmp/daos_first_server_vm)" ]]; then
    return 0 # true
  else
    return 1 # false
  fi
  # set -e
}

gen_certs() {

  if [[ "${DAOS_AZ_CFG_ALLOW_INSECURE,,}" == "true" ]]; then
    log.warn "DAOS_AZ_CFG_ALLOW_INSECURE=true. Certificates will not be used."
    return
  fi

  is_first_server
  if [[ $? -ne 0 ]]; then
    return
  fi

  local secret_count=$(az keyvault secret list --vault-name "${DAOS_AZ_ARM_KEY_VAULT_NAME}" --query "length(@)")
  if [[ "${secret_count}" -eq "7" ]]; then
    log.warn "There are already 7 secrets in the '${DAOS_AZ_ARM_KEY_VAULT_NAME}' key vault. Skipping certificate generation."
    return
  fi

  if [[ -d /tmp/daosCA ]]; then
    log.warn "Certificates already exist in /tmp/daosCA"
  else
    log.info "Generating certificates"
    /opt/daos/lib64/daos/certgen/gen_certificates.sh /tmp
  fi

  kv_set_secret "admin-key" "/tmp/daosCA/certs/admin.key"
  kv_set_secret "admin-crt" "/tmp/daosCA/certs/admin.crt"
  kv_set_secret "agent-key" "/tmp/daosCA/certs/agent.key"
  kv_set_secret "agent-crt" "/tmp/daosCA/certs/agent.crt"
  kv_set_secret "server-key" "/tmp/daosCA/certs/server.key"
  kv_set_secret "server-crt" "/tmp/daosCA/certs/server.crt"
  kv_set_secret "daos-ca-crt" "/tmp/daosCA/certs/daosCA.crt"
}

install_certs() {

  if [[ "${DAOS_AZ_CFG_ALLOW_INSECURE,,}" == "true" ]]; then
    log.warn "DAOS_AZ_CFG_ALLOW_INSECURE=true. Certificates will not be used."
    return
  fi

  local elapsed_secs=0
  local max_wait_secs=300
  local secret_count=0
  local expected_secret_count=7

  secret_count=$(az keyvault secret list --vault-name "${DAOS_AZ_ARM_KEY_VAULT_NAME}" --query "length(@)")

  # Loop until the number of key names is at least 3 or the maximum wait time is reached
  while true; do
    secret_count=$(az keyvault secret list --vault-name "${DAOS_AZ_ARM_KEY_VAULT_NAME}" --query "length(@)")

    if [[ "${secret_count}" -lt "${expected_secret_count}" ]]; then
      log.debug "Number of secret names is ${secret_count}. Expecting ${expected_secret_count} secrets. Waiting 5 seconds..."
      sleep 5
      elapsed_secs=$((elapsed_secs + 5))

      # If the maximum wait time is reached, exit the script
      if [[ "${elapsed_secs}" -ge "${max_wait_secs}" ]]; then
        log.error "Did not find expected ${expected_secret_count} secrets in Key Vault '${DAOS_AZ_ARM_KEY_VAULT_NAME}' after ${elapsed_secs} seconds. Timeout reached. Exiting..."
        exit 1
      fi
    else
      log.debug "Found ${secret_count} secrets in Key Vault '${DAOS_AZ_ARM_KEY_VAULT_NAME}'"

      if [[ "$DAOS_AZ_LOG_LEVEL" == "DEBUG" ]]; then
        log.debug "List of secret names"
        az keyvault secret list --vault-name "${DAOS_AZ_ARM_KEY_VAULT_NAME}" --query "[].name" -o tsv
      fi
      break
    fi
  done

  kv_get_secret "admin-key" "/etc/daos/certs/admin.key"
  kv_get_secret "admin-crt" "/etc/daos/certs/admin.crt"
  kv_get_secret "agent-key" "/etc/daos/certs/agent.key"
  kv_get_secret "agent-crt" "/etc/daos/certs/agent.crt"
  kv_get_secret "server-key" "/etc/daos/certs/server.key"
  kv_get_secret "server-crt" "/etc/daos/certs/server.crt"
  kv_get_secret "daos-ca-crt" "/etc/daos/certs/daosCA.crt"

  chown root:root /etc/daos/certs/*.key
  chown root:root /etc/daos/certs/*.crt
  chmod 400 /etc/daos/certs/*.key
  chmod 644 /etc/daos/certs/*.crt

  mkdir -p /etc/daos/certs/clients
  cp "/etc/daos/certs/agent.crt" "/etc/daos/certs/clients/agent.crt"
}

create_bdev_list() {
  if [[ ! -f /etc/daos/daos_server.yml.orig ]]; then
    log.debug "Creating /etc/daos/daos_server.yml.orig"
    cp /etc/daos/daos_server.yml /etc/daos/daos_server.yml.orig
  fi
  export DAOS_AZ_CFG_BDEV="[\"$(lspci | grep 'Non-Volatile memory controller' | awk '{print $1}')\"]"
}

create_ap_list() {

  awk '{
    hostnames[NR] = $0
  }
  END {
     if (NR == 1 || NR == 3 || NR == 5 || NR == 7) { max = NR }
     else if (NR == 2 || NR == 4 || NR == 6) { max = NR - 1 }
     else if (NR > 7) { max = 7 }

     for (i=1; i<=max; i++) {
         print hostnames[i]
      }
  }' /tmp/daos_server_vmss_vms >/tmp/daos_access_point_vms

  export DAOS_AZ_CFG_AP="[\"$(cat /tmp/daos_access_point_vms | tr ' ' '\n' | xargs | sed 's| |\", \"|g')\"]"
  export DAOS_AZ_CFG_HL="[\"$(cat /tmp/daos_server_vmss_vms | xargs | sed 's| |\", \"|g')\"]"
}

create_configs() {

  create_ap_list
  create_bdev_list

  readarray -t daos_vars < <(compgen -A variable | grep "DAOS_" | sort)
  for var in "${daos_vars[@]}"; do
    export "$var"
  done

  log.info "Creating /etc/daos/daos_agent.yml"
  envsubst <"${SCRIPT_DIR}/daos_agent.yml" >"/etc/daos/daos_agent.yml"

  log.info "Creating /etc/daos/daos_control.yml"
  envsubst <"${SCRIPT_DIR}/daos_control.yml" >"/etc/daos/daos_control.yml"

  log.info "Creating /etc/daos/daos_server.yml"
  envsubst <"${SCRIPT_DIR}/daos_server.yml" >"/etc/daos/daos_server.yml"
}

start_daos_server_service() {
  log.info "Starting daos_server service"
  systemctl enable daos_server.service
  systemctl start daos_server.service
  sleep 5
}

format_storage() {
  is_first_server
  if [[ $? -ne 0 ]]; then
    return
  fi

  local daos_server_status=$(systemctl is-active daos_server)
  if [[ "${daos_server_status}" == "inactive" ]]; then
    log.error "daos_server service is not running. Unable to format storage."
    exit 1
  fi

  # Wait a few seconds for other VMs to start the the daos_server service before
  # attempting to format the storage
  sleep 15
  set +e

  log.info "Formatting DAOS storage"
  dmg storage format

  # Attempt to format servers in a loop until all servers in the VMSS have joined
  local attempts=0
  local max_attempts=20
  local secs_between_attempts=15
  while true; do
    local unformatted_vms=$(comm -13 \
      <(dmg system query -v -j | jq -r '.response.members[] | select(.state == "joined") | .fault_domain' | sed 's|/||g' | sort | tr '[:upper:]' '[:lower:]') \
      <(cat /tmp/daos_server_vmss_vms | sort | tr '[:upper:]' '[:lower:]'))

    log.debug "unformatted_vms = ${unformatted_vms}"

    if [[ -n "${unformatted_vms}" ]]; then
      sleep $secs_between_attempts
      dmg storage format --host-list="$(echo "${unformatted_vms}" | tr ' ' ',')"

      attempts=$((attempts + 1))
      if [[ "${attempts}" -ge "${max_attempts}" ]]; then
        log.error "After ${max_attempts} all servers in '${DAOS_AZ_ARM_SVR_VMSS_NAME}' VM Scale Set are not formatted. Exiting..."
        exit 1
      fi
    else
      break
    fi
  done

  log.info "All servers in '${DAOS_AZ_ARM_SVR_VMSS_NAME}' VM Scale Set joined"
  dmg system query -v
}

create_pool() {
  is_first_server
  if [[ $? -ne 0 ]]; then
    return
  fi

  log.info "Creating pool '${DAOS_AZ_POOL_NAME}'"
  dmg pool create \
    --size="${DAOS_AZ_POOL_SIZE}" \
    --user="root@" \
    --group="root@" \
    --properties="reclaim:lazy" \
    "${DAOS_AZ_POOL_NAME}"

  log.info "Adding pool ACL 'A::OWNER@:rwdtTaAo' on '${DAOS_AZ_POOL_NAME}'"
  dmg pool update-acl --entry "A::OWNER@:rwdtTaAo" "${DAOS_AZ_POOL_NAME}"

  log.info "Adding pool ACL 'A:G:GROUP@:rwtT' on '${DAOS_AZ_POOL_NAME}'"
  dmg pool update-acl --entry "A:G:GROUP@:rwtT" "${DAOS_AZ_POOL_NAME}"

  log.info "Adding pool ACL 'A::EVERYONE@:rcta' on '${DAOS_AZ_POOL_NAME}'"
  dmg pool update-acl --entry "A::EVERYONE@:rcta" "${DAOS_AZ_POOL_NAME}"

}

main() {
  log.info "BEGIN: ${SCRIPT_DIR}/${SCRIPT_FILE}"
  load_env
  az_setup
  wait_for_vmss
  gen_certs
  install_certs
  create_configs
  start_daos_server_service
  format_storage
  create_pool
  log.info "END: ${SCRIPT_DIR}/${SCRIPT_FILE}"
}

main
