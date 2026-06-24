#!/usr/bin/bash
#
# Cluster install helpers (templates, env loading).
#
[[ -n "${CLUSTER_COMMON_SOURCED:-}" ]] && return 0
CLUSTER_COMMON_SOURCED=1

cluster_resolve_paths() {
#
    if [[ -n "${CLUSTER_ROOT_DIR:-}" ]]; then
        CLUSTER_SCRIPT_DIR="${CLUSTER_ROOT_DIR}/cluster"
        CLUSTER_TEMPLATES_DIR="${CLUSTER_SCRIPT_DIR}/templates"
        LIB_DIR="${CLUSTER_ROOT_DIR}/lib"
        return 0
    fi
    local script_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    CLUSTER_SCRIPT_DIR=$(cd "$(dirname "${script_path}")" && pwd)
    CLUSTER_ROOT_DIR=$(cd "${CLUSTER_SCRIPT_DIR}/.." && pwd)
    CLUSTER_TEMPLATES_DIR="${CLUSTER_SCRIPT_DIR}/templates"
    LIB_DIR="${CLUSTER_ROOT_DIR}/lib"
#
}

cluster_load_env() {
#
    local env_file="${1:-${CLUSTER_SCRIPT_DIR}/cluster.env}"
    if [[ -f "${env_file}" ]]; then
        # shellcheck disable=SC1090
        source "${env_file}"
        MYPASSWORD=${MYPASSWORD:-${MYSQL_ROOT_PASSWORD:-}}
        MYSQL_VERSION=${MYSQL_VERSION:-8.0}
        print "Loaded cluster config: ${env_file}" 1
    fi
#
}

cluster_render_template() {
#
    local template="${1}"
    local destination="${2}"
    local content
    [[ -f "${template}" ]] || print_e "Template not found: ${template}"
    content=$(cat "${template}")
    content=${content//@VIP@/${VIP:-}}
    content=${content//@INTERFACE@/${KEEPALIVED_INTERFACE:-eth0}}
    content=${content//@ROUTER_ID@/${KEEPALIVED_ROUTER_ID:-51}}
    content=${content//@PRIORITY@/${KEEPALIVED_PRIORITY:-100}}
    content=${content//@STATE@/${KEEPALIVED_STATE:-MASTER}}
    content=${content//@PEER@/${KEEPALIVED_PEER:-}}
    content=${content//@APP_SERVERS_BLOCK@/${APP_SERVERS_BLOCK:-}}
    content=${content//@SERVER_NAME@/${CLUSTER_DOMAIN:-localhost}}
    content=${content//@DISCOVERY_TYPE@/${OPENSEARCH_DISCOVERY_TYPE:-single-node}}
    content=${content//@NETWORK_HOST@/${OPENSEARCH_BIND_HOST:-0.0.0.0}}
    content=${content//@CLUSTER_NAME@/${OPENSEARCH_CLUSTER_NAME:-bitrix-cluster}}
    content=${content//@NODE_NAME@/${OPENSEARCH_NODE_NAME:-$(hostname -s)}}
    content=${content//@HEAP_SIZE@/${OPENSEARCH_HEAP_SIZE:-1g}}
    printf '%s\n' "${content}" > "${destination}"
#
}

cluster_build_upstream_block() {
#
    APP_SERVERS_BLOCK=""
    local IFS=','
    local entry host port
    for entry in ${APP_SERVERS}; do
        host="${entry%%:*}"
        port="${entry#*:}"
        [[ "${host}" == "${port}" ]] && port="8080"
        APP_SERVERS_BLOCK+="    server ${host}:${port};"$'\n'
    done
#
}

cluster_usage() {
#
    echo "Usage: $0 [-h] [-s] [-c cluster.env] [-r git_repo] [-b branch] [role-specific options]"
    echo "  Git: BITRIX_CLUSTER_REPO, BITRIX_CLUSTER_REF, BITRIX_CLUSTER_CACHE"
    exit "${1:-0}"
#
}

cluster_parse_common_opts() {
#
    CLUSTER_ENV_FILE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h) cluster_usage 0 ;;
            -s) SILENT=1; shift ;;
            -c) CLUSTER_ENV_FILE="$2"; shift 2 ;;
            *) break ;;
        esac
    done
    REMAINING_ARGS=("$@")
#
}

cluster_init() {
#
    cluster_resolve_paths
    # shellcheck disable=SC1091
    source "${LIB_DIR}/bitrix-common.sh"
    bitrix_init_defaults
    bitrix_detect_os
    bitrix_env_vars

    local parsed=()
    CLUSTER_ENV_FILE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h) cluster_usage 0 ;;
            -s) SILENT=1; shift ;;
            -c) CLUSTER_ENV_FILE="$2"; shift 2 ;;
            -r) BITRIX_CLUSTER_REPO="$2"; shift 2 ;;
            -b) BITRIX_CLUSTER_REF="$2"; shift 2 ;;
            *) parsed+=("$1"); shift ;;
        esac
    done
    set -- "${parsed[@]}"

    cluster_load_env "${CLUSTER_ENV_FILE:-${CLUSTER_SCRIPT_DIR}/cluster.env}"
    bitrix_validate_os
#
}
