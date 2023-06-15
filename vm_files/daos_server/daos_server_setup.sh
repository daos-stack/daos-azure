#!/usr/bin/env bash

set -eo pipefail

trap 'echo "daos_server_setup.sh: Unknown error occurred. Exiting' ERR

echo "BEGIN: daos_server_setup.sh"

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
SCRIPT_ENV_FILE="${SCRIPT_FILE%.*}.env"
DAOS_BDEV_ADDR=$(lspci | grep 'Non-Volatile memory controller' | awk '{print $1}')

if [[ -f "${SCRIPT_ENV_FILE}" ]]; then
  source "${SCRIPT_ENV_FILE}"
else
  echo "ERROR: Could not source '${SCRIPT_ENV_FILE}'. File not found."
  echo "Default settings will be used"
fi

DAOS_TIER_RATIO="${DAOS_TIER_RATIO:=3}"
DAOS_POOL_SIZE="${DAOS_POOL_SIZE:="100%"}"
DAOS_POOL_NAME="${DAOS_POOL_NAME:="pool1"}"

# HACK: Need to fix the waagent
#       Disabling it for now because it makes a mess of /var/log/messages
disable_waagent() {
  systemctl stop waagent.service
  systemctl disable waagent.service
}

gen_ap_list() {
  local max_aps=1
  local padded_index=0
  local hostname=""

  if ((DAOS_AZ_serverCount > 5)); then
    max_aps=5
  else
    if ((DAOS_AZ_serverCount == 4)); then
      max_aps=3
    else
      max_aps=$DAOS_AZ_serverCount
    fi
  fi

  for ((i = 0; i < max_aps; i++)); do
    padded_index=$(printf "%06d" $i)
    hostname="${DAOS_VM_BASE_NAME}-${padded_index}"
    if [[ $i -eq 0 ]]; then
      DAOS_FIRST_SERVER="${hostname}"
    fi
    if [ -z "$DAOS_AP_LIST" ]; then
      DAOS_AP_LIST="\"${hostname}\""
    else
      DAOS_AP_LIST="${DAOS_AP_LIST},\"${hostname}\""
    fi
  done
}

gen_config() {

  readarray -t daos_vars < <(compgen -A variable | grep "DAOS" | sort)
  for var in "${daos_vars[@]}"; do
    export "$var"
  done

  echo "Generating /etc/daos/daos_server.yml"
  envsubst <"${SCRIPT_DIR}/config/daos_server.yml.envtpl" >/etc/daos/daos_server.yml

  echo "Generating /etc/daos/daos_control.yml"
  envsubst <"${SCRIPT_DIR}/config/daos_control.yml.envtpl" >/etc/daos/daos_control.yml
}

start_service() {
  systemctl enable daos_server
  systemctl start daos_server
}

prepare_storage() {
  if [[ $(hostname -s) == "${DAOS_FIRST_SERVER}" ]]; then
    # FIX: The following sleep statement assumes that 60 seconds is enough time
    #      for all VMs in the scale set to be deployed and start the daos_server.
    #      This is not a good solution. There is no guarantee that the VMs will
    #      be ready in that amount of time. We need to replace this with a loop
    #      around an API call to get the state of the VMs in the scale set and
    #      ensure they are all up and the daos_server service is running before
    #      we attempt to run `dmg storage format`.
    #      See https://daosio.atlassian.net/browse/DAOSAZ-15
    sleep 60
    dmg storage format
    dmg system query -v
    # FIX: The following sleep statement was added because errors were occuring
    # when pool create was run immediately after dmg system query returned.
    # Needs investigation.
    sleep 10
    if [[ "${DAOS_POOL_SIZE}" == "100%" ]]; then
      dmg pool create --size="${DAOS_POOL_SIZE}" "${DAOS_POOL_NAME}"
    else
      dmg pool create --size="${DAOS_POOL_SIZE}" --tier-ratio="${DAOS_TIER_RATIO}" "${DAOS_POOL_NAME}"
    fi
    # FIX: The following sleep statement was added because errors were occuring
    # when pool update-acl was run immediately after dmg system query returned.
    # Needs investigation.
    sleep 10
    dmg pool update-acl -e 'A::EVERYONE@:rcta' "${DAOS_POOL_NAME}"
  fi
}

main() {
  disable_waagent
  gen_ap_list
  gen_config
  start_service
  prepare_storage
  echo "END: daos_server_setup.sh"
}

main
