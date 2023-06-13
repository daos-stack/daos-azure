#!/usr/bin/env bash

set -eo pipefail

trap 'echo "daos_client_setup.sh : Unknown error occurred. Exiting."' ERR

echo "BEGIN: daos_client_setup.sh"

SCRIPT_DIR="$(realpath "$(dirname $0)")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
SCRIPT_ENV_FILE="${SCRIPT_FILE%.*}.env"

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
  # TODO: Figure out how this should be set

  # Slurm style host list not working right now
  # See https://daosio.atlassian.net/browse/DAOS-13662
  #DAOS_AP_LIST="${DAOS_VM_BASE_NAME}-[000000-$(printf "%06d" $(($max_aps - 1)))]"

  export DAOS_AP_LIST='"maolson-daos-server-000000","maolson-daos-server-000001","maolson-daos-server-000002"'
}

gen_config() {

  echo "DAOS_AP_LIST=${DAOS_AP_LIST}"

  echo "Generating /etc/daos/daos_agent.yml"
  envsubst <"${SCRIPT_DIR}/config/daos_agent.yml.envtpl" >/etc/daos/daos_agent.yml

  echo "Generating /etc/daos/daos_control.yml"
  envsubst <"${SCRIPT_DIR}/config/daos_control.yml.envtpl" >/etc/daos/daos_control.yml

  mkdir -p /var/daos
  chmod 0755 /var/daos
}

start_service() {
  systemctl enable daos_agent
  systemctl start daos_agent
}

gen_cont_script() {
  # Generate script to create and mount container
  cat >/home/daos_admin/create_and_mount_cont.sh <<'EOF'
#!/usr/bin/env bash

DAOS_POOL_NAME="pool1"
DAOS_CONT_NAME="cont1"

echo "Creating container '${DAOS_CONT_NAME}' in pool '${DAOS_POOL_NAME}'"
daos container create --type=POSIX --properties=rf:0 "${DAOS_POOL_NAME}" "${DAOS_CONT_NAME}"

MOUNT_DIR="${HOME}/daos/${DAOS_CONT_NAME}"
mkdir -p "${MOUNT_DIR}"

dfuse --singlethread --pool="${DAOS_POOL_NAME}" --container="${DAOS_CONT_NAME}" --mountpoint="${MOUNT_DIR}"
df -h -t fuse.daos

echo
echo
echo "To create a large file in the container"
echo "cd ${MOUNT_DIR}"
echo "time LD_PRELOAD=/usr/lib64/libioil.so dd if=/dev/zero of=./test21G.img bs=1G count=20"
echo
echo "To use the intercept library"
echo "time LD_PRELOAD=/usr/lib64/libpil4dfs.so dd if=/dev/zero of=./test21G.img bs=1G count=20"
echo

EOF

  chmod 755 /home/daos_admin/create_and_mount_cont.sh
  chown daos_admin:daos_admin /home/daos_admin/create_and_mount_cont.sh
}

main() {
  load_env
  disable_waagent
  gen_ap_list
  gen_config
  start_service
  gen_cont_script
  echo "END: daos_client_setup.sh"
}

main
