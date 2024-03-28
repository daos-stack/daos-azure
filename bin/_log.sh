#!/usr/bin/env bash
# Copyright (c) 2024 Intel Corporation All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# This file is meant to be sourced by other scripts.
# Logging functions

: "${DAOS_AZ_LOG_LEVEL:="INFO"}"
: "${LOG_COLS:="80"}"
: "${LOG_LINE_CHAR:="-"}"

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
  local var_prefix="${1:-"DAOS_"}"
  local daos_vars

  if [[ "${DAOS_AZ_LOG_LEVEL}" == "DEBUG" ]]; then
    log.debug && log.debug "ENVIRONMENT VARIABLES" && log.debug "---"
    readarray -t daos_vars < <(compgen -A variable | grep "${var_prefix}" | sort)
    for item in "${daos_vars[@]}"; do
      log.debug "${item}=${!item}"
    done
    echo
  fi
}

log.line() {
  local line_char="${1:-$LOG_LINE_CHAR}"
  local line_width="${2:-$LOG_COLS}"
  local fg_color="${3:-${LOG_COLORS['OTHER']}}"
  local line
  line=$(printf "%${line_width}s" | tr " " "${line_char}")
  if [[ ${LOG_LEVELS[${DAOS_AZ_LOG_LEVEL}]} -le ${LOG_LEVELS[OFF]} ]]; then
    if [[ -t 1 ]]; then tput setaf "${fg_color}"; fi
    printf -- "%s\n" "${line}" 1>&2
    if [[ -t 1 ]]; then tput sgr0; fi
  fi
}

log.section() {
  # log.section msg [line_width] [line_char] [fg_color]
  local msg="${1:-}"
  local line_width="${2:-$LOG_COLS}"
  local line_char="${3:-$LOG_LINE_CHAR}"
  local fg_color="${4:-${LOG_COLORS['OTHER']}}"
  if [[ ${LOG_LEVELS[${DAOS_AZ_LOG_LEVEL}]} -le ${LOG_LEVELS[OFF]} ]]; then
    log.line "${line_char}" "${line_width}" "${fg_color}"
    if [[ -t 1 ]]; then tput setaf "${fg_color}"; fi
    echo -e "${msg}" 1>&2
    log.line "${line_char}" "${line_width}" "${fg_color}"
    if [[ -t 1 ]]; then tput sgr0; fi
  fi
}
