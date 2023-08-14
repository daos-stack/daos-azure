# This file contains logging functions and is sourced by other scripts.

: "${DAOS_AZ_LOG_LEVEL:="INFO"}"

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
  local var_prefix="${1}"
  local daos_vars

  if [[ -z "${var_prefix}" ]]; then
    var_prefix="DAOS"
  fi

  if [[ "${DAOS_AZ_LOG_LEVEL}" == "DEBUG" ]]; then
    log.debug && log.debug "ENVIRONMENT VARIABLES" && log.debug "---"
    readarray -t daos_vars < <(compgen -A variable | grep "${var_prefix}" | sort)
    for item in "${daos_vars[@]}"; do
      log.debug "${item}=${!item}"
    done
    log.debug "---"
  fi
}

log.debug.vars() {
  local vars_grep_regex="DAOS_"
  if [[ "${DAOS_AZ_LOG_LEVEL}" == "DEBUG" ]]; then
    local script_vars
    echo
    log.debug "=== Environment variables ==="
    readarray -t script_vars < <(compgen -A variable | grep "${vars_grep_regex}" | sort)
    for script_var in "${script_vars[@]}"; do
      log.debug "${script_var}=${!script_var}"
    done
    echo
  fi
}
