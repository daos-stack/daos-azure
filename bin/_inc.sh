#!/usr/bin/env bash
# Copyright (c) 2024 Intel Corporation All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.
# This file is meant to be sourced by other scripts.
# Requires the the bin/_log.sh file to be sourced before sourcing this file.

inc.env_export() {
  readarray -t daos_vars < <(compgen -A variable | grep "DAOS_" | sort)
  for var in "${daos_vars[@]}"; do
    # shellcheck disable=SC2163
    export "$var"
  done
}

inc.env_load() {
  local env_file="${1}"
  if [[ -n "${env_file}" ]]; then
    if [[ -f "${env_file}" ]]; then
      log.debug "Sourcing ${env_file}"
      # shellcheck disable=SC2163,SC1090
      source "${env_file}"
    else
      log.error "File not found: ${env_file}"
      exit 1
    fi
  fi
}
