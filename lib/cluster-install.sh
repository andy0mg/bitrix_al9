#!/usr/bin/bash
#
# Shared header for cluster role install scripts.
# shellcheck disable=SC1091
cluster_install_begin() {
    local role="${1}"
    local self="${2}"
    BITRIX_CLUSTER_ROLE="${role}"
    local script_dir
    script_dir=$(cd "$(dirname "${self}")" && pwd)
    if [[ -f "${script_dir}/../lib/cluster-fetch.sh" ]]; then
        source "${script_dir}/../lib/cluster-fetch.sh"
    elif [[ -f "${BITRIX_CLUSTER_CACHE:-/var/cache/bitrix-cluster}/lib/cluster-fetch.sh" ]]; then
        source "${BITRIX_CLUSTER_CACHE}/lib/cluster-fetch.sh"
    else
        echo "cluster-fetch.sh not found. Use cluster/run.sh or set BITRIX_CLUSTER_REPO." >&2
        exit 1
    fi
    cluster_prepare_role "${BITRIX_CLUSTER_ROLE}" || exit 1
    source "${LIB_DIR}/cluster-common.sh"
    cluster_init "${@:3}"
}
