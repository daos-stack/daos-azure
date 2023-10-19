#!/usr/bin/env bash
# Copyright (c) 2023 Intel Corporation All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.


set -eo pipefail

mkdir -p /var/log/daos
exec 3>&1
exec > >(tee /var/log/daos/daos_server_setup.log) 2>&1

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
    DAOS_SERVER_ANSIBLE_COLL_URL="${DAOS_SERVER_ANSIBLE_COLL_URL:="git+https://github.com/daos-stack/ansible-collection-daos.git"}"
    DAOS_SERVER_ANSIBLE_PLAYBOOK="${DAOS_SERVER_ANSIBLE_PLAYBOOK:="daos_stack.daos.azure.daos_server"}"
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

  local daos_coll_path="/root/.ansible/collections/ansible_collections/daos_stack/daos"
  if [[ -e "${daos_coll_path}" ]]; then
    echo "daos_stack.daos ansible collection already installed"
  else
    echo "Installing daos_stack.daos ansible collection"
    ansible-galaxy collection install "${DAOS_SERVER_ANSIBLE_COLL_URL}"
    ansible-galaxy install -r "${daos_coll_path}/requirements.yml"
    pip install -r "${daos_coll_path}/requirements.txt"
  fi
}

install_daos() {
  ansible-playbook -c local -i '127.0.0.1,' "${DAOS_SERVER_ANSIBLE_PLAYBOOK}" \
    --extra-vars="{
      subscription: \"${DAOS_AZ_CORE_ACCT_NAME}\",
      group_name: \"${DAOS_AZ_CORE_RG_NAME}\",
      location: \"${DAOS_AZ_CORE_LOCATION}\",
      vmss_name: \"${DAOS_AZ_ARM_SERVER_VMSS_NAME}\",
      vault_name: \"${DAOS_AZ_ARM_KEY_VAULT_NAME}\"
    }"
}

create_host_list_files() {
  az vmss list-instances \
    --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --name "${DAOS_AZ_ARM_SERVER_VMSS_NAME}" \
    --query "[].osProfile.computerName" \
    --out tsv > hosts_servers
}

create_ssh_config() {
  mkdir -p /home/daos_admin/.ssh
  chmod 700 /home/daos_admin/.ssh
  cat > /home/daos_admin/.ssh/config <<EOF
Host *
    LogLevel error
    CheckHostIp no
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
    PreferredAuthentications publickey,password
    ForwardAgent yes
    TCPKeepAlive yes
    ServerAliveInterval 60
    ServerAliveCountMax 5
EOF
  chmod 600 /home/daos_admin/.ssh/config
  chown -R daos_admin:daos_admin /home/daos_admin/.ssh

  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  cp -f /home/daos_admin/.ssh/config /root/.ssh/config
  chmod 600 /root/.ssh/config
  chown -R root:root /root/.ssh
}

main() {
  echo "BEGIN: ${SCRIPT_DIR}/${SCRIPT_FILE}"
  load_env
  install_ansible
  install_daos
  create_host_list_files
  create_ssh_config
  echo "END: ${SCRIPT_DIR}/${SCRIPT_FILE}"
}

main
