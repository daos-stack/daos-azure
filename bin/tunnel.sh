#!/usr/bin/env bash
# Copyright (c) 2024 Intel Corporation All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -eo pipefail

trap 'echo "${BASH_SOURCE[0]} : Unexpected error. Exiting."' ERR

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../daos-azure.env"
DAOS_AZ_ENV_FILE="${DAOS_AZ_ENV_FILE:="${DEFAULT_ENV_FILE}"}"

TUNNEL_ACTION=""
TUNNEL_SSH_UPDATE_CONFIG="false"
TUNNEL_LOCAL_PORT=2022
TUNNEL_SSH_INCLUDE_DIR="${HOME}/.ssh/config.d"
TUNNEL_SSH_CONFIG_FILE="${TUNNEL_SSH_INCLUDE_DIR}/azure-tunnel"


# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_log.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_inc.sh"

show_help() {

  echo "

Manage Azure Bastion tunnel for DAOS client deployments

Usage:

  ${SCRIPT_FILE} [<options>]

Options:

  [ -e | --env-file DAOS_AZ_ENV_FILE ]  Use specified environment file
  [ -l | --list ]     List tunnel(s)
  [ -c | --create ]   Create tunnel
  [ -d | --delete ]   Delete tunnel
  [ -p | --print ]    Print SSH configuration. Do not modify ~/.ssh/config
  [ --configure-ssh ] Update ~/.ssh/config with include path
  [ -h | --help ]     Show this help

"

}

vmss_check() {
  local vmss_list
  vmss_list=$(az vmss list -g "${DAOS_AZ_CORE_RG_NAME}" --query "[].name" -o tsv)
  if [[ "${vmss_list}" == "" ]]; then
    log.error "No Virtual Machine Scale Sets exist in resource group '${DAOS_AZ_CORE_RG_NAME}'. Exiting."
    exit 1
  fi

  # Attempt to tunnel to the 1st client VM if it exists; otherwise use the 1st server VM.
  if echo "$vmss_list" | grep -q "${DAOS_AZ_ARM_CLIENT_VMSS_NAME}"; then
    TUNNEL_HOSTNAME_PREFIX="$(az vmss show -g "${DAOS_AZ_CORE_RG_NAME}" --name "${DAOS_AZ_ARM_CLIENT_VMSS_NAME}" --query "virtualMachineProfile.osProfile.computerNamePrefix" -o tsv | sed 's/.$//' | sed 's/-client//g')"
    TUNNEL_FIRST_VM_NAME=$(az vmss list-instances -g "${DAOS_AZ_CORE_RG_NAME}" --name "${DAOS_AZ_ARM_CLIENT_VMSS_NAME}" --query "[?instanceId=='0'].osProfile.computerName" -o tsv)
    TUNNEL_FIRST_VM_ID=$(az vmss list-instances --resource-group "${DAOS_AZ_CORE_RG_NAME}" --name "${DAOS_AZ_ARM_CLIENT_VMSS_NAME}" --query "[?instanceId=='0'].id" -o tsv)
  elif echo "$vmss_list" | grep -q "${DAOS_AZ_ARM_SERVER_VMSS_NAME}"; then
    TUNNEL_HOSTNAME_PREFIX="$(az vmss show -g "${DAOS_AZ_CORE_RG_NAME}" --name "${DAOS_AZ_ARM_SERVER_VMSS_NAME}" --query "virtualMachineProfile.osProfile.computerNamePrefix" -o tsv | sed 's/.$//' | sed 's/-client//g')"
    TUNNEL_FIRST_VM_NAME=$(az vmss list-instances -g "${DAOS_AZ_CORE_RG_NAME}" --name "${DAOS_AZ_ARM_SERVER_VMSS_NAME}" --query "[?instanceId=='0'].osProfile.computerName" -o tsv)
    TUNNEL_FIRST_VM_ID=$(az vmss list-instances --resource-group "${DAOS_AZ_CORE_RG_NAME}" --name "${DAOS_AZ_ARM_SERVER_VMSS_NAME}" --query "[?instanceId=='0'].id" -o tsv)
  fi
  return $?
}

configure_ssh() {
  if [[ "${TUNNEL_SSH_UPDATE_CONFIG,,}" == "true" ]]; then
    # shellcheck disable=SC2174
    [[ ! -d ~/.ssh ]] && mkdir -m 700 -p ~/.ssh
    # shellcheck disable=SC2174
    [[ ! -d "${TUNNEL_SSH_INCLUDE_DIR}" ]] && mkdir -m 700 -p "${TUNNEL_SSH_INCLUDE_DIR}"
    touch ~/.ssh/config && chmod 600 ~/.ssh/config
    if ! grep -E -q "Include\\s+${TUNNEL_SSH_INCLUDE_DIR}/\\*" ~/.ssh/config; then
      log.info "Adding 'Include ${TUNNEL_SSH_INCLUDE_DIR}/*' to ~/.ssh/config"
      echo "Include ${TUNNEL_SSH_INCLUDE_DIR}/*" >> ~/.ssh/config
    fi
  fi
}

create_ssh_config() {
  local ssh_config_file="$1"

  cat > "${ssh_config_file}" <<EOF
Host jump
    Hostname 127.0.0.1
    Port ${TUNNEL_LOCAL_PORT}
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
    IdentitiesOnly yes
    User ${DAOS_AZ_ARM_ADMIN_USER}
    IdentityFile ${DAOS_AZ_SSH_ADMIN_KEY}

Host ${TUNNEL_HOSTNAME_PREFIX}*
    ProxyJump jump
    CheckHostIp no
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
    User ${DAOS_AZ_ARM_ADMIN_USER}
    IdentitiesOnly yes
    IdentityFile ${DAOS_AZ_SSH_ADMIN_KEY}

EOF
}

print_ssh_config() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local tmp_file
  tmp_file="${tmp_dir}/ssh_config"

  create_ssh_config "${tmp_file}"
  cat "${tmp_file}"
  if [[ -d "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}"
  fi
}

delete_ssh_config() {
  if [[ -f "${TUNNEL_SSH_CONFIG_FILE}" ]]; then
    rm -f "${TUNNEL_SSH_CONFIG_FILE}"
  fi
}

create_tunnel() {
  local existing_tunnel_pid
  set +e
  existing_tunnel_pid=$(lsof -i "tcp:${TUNNEL_LOCAL_PORT}" | grep 'TCP localhost:down (LISTEN)' | awk '{print $2}')
  if [[ -n "${existing_tunnel_pid}" ]]; then
    log.info "A tunnel on port '${TUNNEL_LOCAL_PORT}' already exists. PID: ${existing_tunnel_pid}"
    exit 0
  fi
  set -e
  log.info "Creating SSH tunnel through '${DAOS_AZ_ARM_BASTION_NAME}' bastion to '${TUNNEL_FIRST_VM_NAME}'"

  log.debug "
  az network bastion tunnel \\
    --subscription \"${DAOS_AZ_CORE_ACCT_NAME}\" \\
    --resource-group \"${DAOS_AZ_CORE_RG_NAME}\" \\
    --name \"${DAOS_AZ_ARM_BASTION_NAME}\" \\
    --target-resource-id \"${TUNNEL_FIRST_VM_ID}\" \\
    --resource-port \"22\" \\
    --port \"${TUNNEL_LOCAL_PORT}\"
  "

  az network bastion tunnel \
    --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --name "${DAOS_AZ_ARM_BASTION_NAME}" \
    --target-resource-id "${TUNNEL_FIRST_VM_ID}" \
    --resource-port "22" \
    --port "${TUNNEL_LOCAL_PORT}" >/dev/null 2>&1 &

  log.info "Creating SSH config: '${TUNNEL_SSH_CONFIG_FILE}'"
  create_ssh_config "${TUNNEL_SSH_CONFIG_FILE}"

  log.info "Tunnel through '${TUNNEL_FIRST_VM_NAME}' is now running on 127.0.0.1:${TUNNEL_LOCAL_PORT}"
}

list_tunnels() {
  if lsof -i "tcp:${TUNNEL_LOCAL_PORT}" | grep -q '(LISTEN)'; then
    log.info "Tunnel on '${TUNNEL_LOCAL_PORT}' through '${DAOS_AZ_ARM_BASTION_NAME} exists"
    lsof -i "tcp:${TUNNEL_LOCAL_PORT}"
  else
    echo "No tunnel on port '${TUNNEL_LOCAL_PORT}' exists"
  fi
}

delete_tunnel() {
  log.debug "delete_tunnel()"
  set +e
  EXISTING_TUNNEL_PID=$(lsof -i "tcp:${TUNNEL_LOCAL_PORT}" | grep 'TCP localhost:down (LISTEN)' | grep -v grep | awk '{print $2}')
  if [[ -n $EXISTING_TUNNEL_PID ]]; then
    log.info "Deleting tunnel on port '${TUNNEL_LOCAL_PORT}', PID: $EXISTING_TUNNEL_PID"
    kill -9 "$EXISTING_TUNNEL_PID"
    delete_ssh_config
  else
    log.info "Tunnel does not exist on port ${TUNNEL_LOCAL_PORT}. No tunnel to delete."
  fi
  set -e
}

opts() {
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
    --print | -p)
      TUNNEL_ACTION="print"
      break
      ;;
    --list | -l)
      TUNNEL_ACTION="list"
      shift
      ;;
    --create | -c)
      TUNNEL_ACTION="create"
      shift
      ;;
    --delete | -d)
      TUNNEL_ACTION="delete"
      shift
      ;;
    --configure-ssh)
      TUNNEL_SSH_UPDATE_CONFIG="true"
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
  inc.env_load "${DAOS_AZ_ENV_FILE}"
  vmss_check
  configure_ssh
  case "${TUNNEL_ACTION}" in
    print)
      print_ssh_config
      ;;
    list)
      list_tunnels
      ;;
    create)
      create_tunnel
      ;;
    delete)
      delete_tunnel
      ;;
  esac
}

main "$@"
