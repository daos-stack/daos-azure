#!/usr/bin/env bash
# Copyright (c) 2023 Intel Corporation All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.


set -eo pipefail

mkdir -p /var/log/daos
exec 3>&1
exec > >(tee /var/log/daos/daos_client_setup.log) 2>&1

trap 'error_handler' ERR

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SCRIPT_FILE=$(basename "${BASH_SOURCE[0]}")

error_handler() {
  exec 3>&-
  echo "ERROR: An unknown error occurred"
  echo "ERROR: Exiting ${SCRIPT_DIR}/${SCRIPT_FILE}"
}

load_env() {
  env_file="${SCRIPT_DIR}/${SCRIPT_FILE%.*}.env"
  if [[ -f "${env_file}" ]]; then
    echo "Sourcing ${env_file}"
    # shellcheck disable=SC1090
    source "${env_file}"
    DAOS_ANSIBLE_COLL_URL="${DAOS_ANSIBLE_COLL_URL:="git+https://github.com/daos-stack/ansible-collection-daos.git"}"
    DAOS_ANSIBLE_PLAYBOOK="${DAOS_ANSIBLE_PLAYBOOK:="daos_stack.daos.azure.daos_client"}"
  else
    echo "ERROR: File not found: '${env_file}'. Exiting..."
    exit 1
  fi
}

install_ansible() {
  set +e
  setenforce 0
  set -e
  dnf -y install epel-release
  dnf -y install python3.11 python3.11-pip curl wget ansible-core
  if [[ ! -f /root/.venv/bin/python3 ]]; then
    echo "Creating virtualenv: /root/.venv"
    /usr/bin/python3.11 -m venv /root/.venv
    echo 'export ANSIBLE_PYTHON_INTERPRETER=/root/.venv/bin/python3' >> /root/.bashrc
  fi

  # shellcheck disable=SC1090,SC1091
  source /root/.venv/bin/activate
  pip install pip --upgrade

  export ANSIBLE_PYTHON_INTERPRETER=/root/.venv/bin/python3

  ansible-galaxy collection install "azure.azcollection"
  pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt

  ansible-galaxy collection install --force "${DAOS_ANSIBLE_COLL_URL}"
  ansible-galaxy install -r ~/.ansible/collections/ansible_collections/daos_stack/daos/requirements.yml
  pip install -r ~/.ansible/collections/ansible_collections/daos_stack/daos/requirements.txt
}

install_daos() {
  ansible-playbook -c local -i '127.0.0.1,' "${DAOS_ANSIBLE_PLAYBOOK}" \
    --extra-vars="{
      subscription: \"${DAOS_AZ_CORE_ACCT_NAME}\",
      group_name: \"${DAOS_AZ_CORE_RG_NAME}\",
      location: \"${DAOS_AZ_CORE_LOCATION}\",
      vmss_name: \"${DAOS_AZ_ARM_SERVER_VMSS_NAME}\",
      vault_name: \"${DAOS_AZ_ARM_KEY_VAULT_NAME}\",
      server_host_list: ${DAOS_AZ_SERVER_HOST_LIST}
    }"
}

main() {
  echo "BEGIN: ${SCRIPT_DIR}/${SCRIPT_FILE}"
  load_env
  install_ansible
  install_daos
  echo "END: ${SCRIPT_DIR}/${SCRIPT_FILE}"
}

main
