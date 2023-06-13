#!/usr/bin/env bash

set -eo pipefail

# trap 'error_handler' ERR
# trap 'cleanup' SIGINT
echo "BEGIN: daos_server_setup.sh"

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
SCRIPT_ENV_FILE="${SCRIPT_FILE%.*}.env"
DAOS_BDEV_ADDR=$(lspci | grep 'Non-Volatile memory controller' | awk '{print $1}')
DAOS_SERVER_SYSTEMD_FILE="/etc/systemd/system/daos_server.service"
DAOS_SCM_SIZE=40
DAOS_TIER_RATIO=3
DAOS_POOL_SIZE=4TB

# Source Environment Variables
load_env() {
  if [[ -f "${SCRIPT_ENV_FILE}" ]]; then
    source "${SCRIPT_ENV_FILE}"
  else
    echo "ERROR: Could not source '${SCRIPT_ENV_FILE}'. File not found."
    #error_handler
    exit 1
  fi
}

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

  # Slurm style host list not working right now
  # See https://daosio.atlassian.net/browse/DAOS-13662
  #DAOS_AP_LIST="${DAOS_VM_BASE_NAME}-[000000-$(printf "%06d" $(($max_aps - 1)))]"

  # Have to generate access_points list that contains individual hosts
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

  # readarray -t daos_vars < <(compgen -A variable | grep "DAOS" | sort)
  # for var in "${daos_vars[@]}"; do
  #   export "$var"
  #   log.debug "Exported: $var=${daos_vars[$var]}"
  # done
  echo "DAOS_BDEV_ADDR=${DAOS_BDEV_ADDR}"
  echo "DAOS_AP_LIST=${DAOS_AP_LIST}"
  echo "DAOS_FIRST_SERVER=${DAOS_FIRST_SERVER}"

  export DAOS_BDEV_ADDR
  export DAOS_AP_LIST
  export DAOS_FIRST_SERVER
  export DAOS_AZ_serverCount
  export DAOS_SCM_SIZE

  echo "Generating /etc/daos/daos_server.yml"
  envsubst <"${SCRIPT_DIR}/config/daos_server.yml.envtpl" >/etc/daos/daos_server.yml

  echo "Generating /etc/daos/daos_control.yml"
  envsubst <"${SCRIPT_DIR}/config/daos_control.yml.envtpl" >/etc/daos/daos_control.yml
}

start_service() {
  systemctl enable daos_server
  systemctl start daos_server
}

load_env
disable_waagent
gen_ap_list
gen_config
start_service

if [[ $(hostname -s) == "${DAOS_FIRST_SERVER}" ]]; then
  sleep 20
  dmg storage format
  dmg system query -v

  #DAOS_TOTAL_NVME_FREE="$(dmg storage query usage | awk '{split($0,a," "); sum += a[10]} END {print sum}')TB"
  #echo "Total NVMe-Free: ${DAOS_TOTAL_NVME_FREE}"
  # FIX: Need to calculate the pool size properly based on amount of storage and tier ratio
  #      Right now there is not enough memory for SCM to use all the available disk space.
  dmg pool create --size="${DAOS_POOL_SIZE}" --tier-ratio="${DAOS_TIER_RATIO}" pool1
  dmg pool get-acl pool1
  dmg pool update-acl -e 'A::EVERYONE@:rcta' pool1
fi

echo "END: daos_server_setup.sh"
