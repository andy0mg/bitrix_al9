#!/usr/bin/bash
#
# Fetch install scripts and role assets from a git repository.
#
[[ -n "${CLUSTER_FETCH_SOURCED:-}" ]] && return 0
CLUSTER_FETCH_SOURCED=1

BITRIX_CLUSTER_REF="${BITRIX_CLUSTER_REF:-main}"
BITRIX_CLUSTER_CACHE="${BITRIX_CLUSTER_CACHE:-/var/cache/bitrix-cluster}"

cluster_role_paths() {
#
    local role="${1}"
    local common="
lib/bitrix-common.sh
lib/cluster-common.sh
lib/cluster-fetch.sh
lib/cluster-install.sh
cluster/cluster.env.example
"
    case "${role}" in
        balancer)
            printf '%s\n' ${common} \
                cluster/install-balancer.sh \
                cluster/templates/nginx-upstream.conf.tpl \
                cluster/templates/http_balancer.conf.tpl \
                cluster/templates/keepalived.conf.tpl
            ;;
        app)
            printf '%s\n' ${common} \
                cluster/install-app.sh \
                cluster/templates/transformer/transformer.env.tpl
            ;;
        push)
            printf '%s\n' ${common} \
                cluster/install-push.sh \
                cluster/templates/push-server-multi.tpl
            ;;
        mysql-master)
            printf '%s\n' ${common} \
                cluster/install-mysql-master.sh \
                cluster/templates/mysql-master.cnf.d/replication.cnf
            ;;
        mysql-slave)
            printf '%s\n' ${common} \
                cluster/install-mysql-slave.sh \
                cluster/templates/mysql-slave.cnf.d/replication.cnf
            ;;
        opensearch)
            printf '%s\n' ${common} \
                cluster/install-opensearch.sh \
                cluster/templates/opensearch.yml.tpl
            ;;
        *)
            echo "Unknown role: ${role}" >&2
            return 1
            ;;
    esac
#
}

cluster_repo_to_raw() {
#
    local repo="${1}"
    local ref="${2}"
    if [[ "${repo}" == https://github.com/* ]]; then
        repo="${repo%.git}"
        repo="${repo#https://github.com/}"
        echo "https://raw.githubusercontent.com/${repo}/${ref}"
        return 0
    fi
    if [[ "${repo}" == git@github.com:* ]]; then
        repo="${repo#git@github.com:}"
        repo="${repo%.git}"
        echo "https://raw.githubusercontent.com/${repo}/${ref}"
        return 0
    fi
    return 1
#
}

cluster_fetch_file_curl() {
#
    local raw_base="${1}"
    local rel_path="${2}"
    local dest="${BITRIX_CLUSTER_CACHE}/${rel_path}"
    mkdir -p "$(dirname "${dest}")"
    curl -fsSL "${raw_base}/${rel_path}" -o "${dest}"
#
}

cluster_fetch_role_curl() {
#
    local role="${1}"
    local raw_base="${2}"
    local rel_path
    while IFS= read -r rel_path; do
        [[ -n "${rel_path}" ]] || continue
        cluster_fetch_file_curl "${raw_base}" "${rel_path}"
    done < <(cluster_role_paths "${role}")
#
}

cluster_ensure_git_repo() {
#
    local role="${1}"
    if [[ -d "${BITRIX_CLUSTER_CACHE}/.git" ]]; then
        git -C "${BITRIX_CLUSTER_CACHE}" fetch --depth 1 origin "${BITRIX_CLUSTER_REF}" >> /dev/null 2>&1
        git -C "${BITRIX_CLUSTER_CACHE}" checkout "${BITRIX_CLUSTER_REF}" >> /dev/null 2>&1
        git -C "${BITRIX_CLUSTER_CACHE}" reset --hard "FETCH_HEAD" >> /dev/null 2>&1
        return 0
    fi
    rm -rf "${BITRIX_CLUSTER_CACHE}"
    git clone --depth 1 --branch "${BITRIX_CLUSTER_REF}" "${BITRIX_CLUSTER_REPO}" "${BITRIX_CLUSTER_CACHE}"
#
}

cluster_ensure_role_sources() {
#
    local role="${1}"
    local raw_base

    [[ -n "${role}" ]] || return 1

    if [[ -n "${BITRIX_CLUSTER_RAW:-}" ]]; then
        raw_base="${BITRIX_CLUSTER_RAW%/}"
    elif [[ -n "${BITRIX_CLUSTER_REPO:-}" ]]; then
        raw_base="$(cluster_repo_to_raw "${BITRIX_CLUSTER_REPO}" "${BITRIX_CLUSTER_REF}")" || true
    fi

    if [[ -n "${BITRIX_CLUSTER_REPO:-}" ]] && command -v git >> /dev/null 2>&1; then
        cluster_ensure_git_repo "${role}"
    elif [[ -n "${raw_base}" ]]; then
        mkdir -p "${BITRIX_CLUSTER_CACHE}"
        cluster_fetch_role_curl "${role}" "${raw_base}"
    else
        echo "Set BITRIX_CLUSTER_REPO (git URL) or BITRIX_CLUSTER_RAW (raw base URL)." >&2
        echo "Example: export BITRIX_CLUSTER_REPO=https://github.com/you/bitrix_al9.git" >&2
        return 1
    fi

    local rel_path
    while IFS= read -r rel_path; do
        [[ -f "${BITRIX_CLUSTER_CACHE}/${rel_path}" ]] || {
            echo "Missing after fetch: ${rel_path}" >&2
            return 1
        }
    done < <(cluster_role_paths "${role}")
#
}

cluster_set_paths_from_root() {
#
    local root="${1}"
    CLUSTER_ROOT_DIR="${root}"
    CLUSTER_SCRIPT_DIR="${CLUSTER_ROOT_DIR}/cluster"
    CLUSTER_TEMPLATES_DIR="${CLUSTER_SCRIPT_DIR}/templates"
    LIB_DIR="${CLUSTER_ROOT_DIR}/lib"
#
}

cluster_prepare_role() {
#
    local role="${1}"
    local caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local caller_dir

    caller_dir=$(cd "$(dirname "${caller}")" && pwd)

    if [[ -f "${caller_dir}/../lib/bitrix-common.sh" ]]; then
        cluster_set_paths_from_root "$(cd "${caller_dir}/.." && pwd)"
        return 0
    fi

    if [[ -f "${BITRIX_CLUSTER_CACHE}/lib/bitrix-common.sh" ]]; then
        local rel_path
        local missing=0
        while IFS= read -r rel_path; do
            [[ -f "${BITRIX_CLUSTER_CACHE}/${rel_path}" ]] || missing=1
        done < <(cluster_role_paths "${role}")
        if [[ ${missing} -eq 0 ]]; then
            cluster_set_paths_from_root "${BITRIX_CLUSTER_CACHE}"
            return 0
        fi
    fi

    cluster_ensure_role_sources "${role}" || return 1
    cluster_set_paths_from_root "${BITRIX_CLUSTER_CACHE}"
#
}
