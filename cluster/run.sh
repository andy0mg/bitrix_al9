#!/usr/bin/bash
#
# Remote entry point: fetch role assets from git and run install script.
#
#   curl -fsSL https://raw.githubusercontent.com/ORG/bitrix_al9/main/cluster/run.sh -o /tmp/bitrix-run.sh
#   chmod +x /tmp/bitrix-run.sh
#   /tmp/bitrix-run.sh -c /etc/bitrix-cluster.env app -s -H app1
#
set -u

RUN_SELF="${BASH_SOURCE[0]}"
RUN_DIR=$(cd "$(dirname "${RUN_SELF}")" && pwd)

usage() {
    cat <<'EOF'
Usage: run.sh [-r git_repo] [-b branch] [-c cluster.env] <role> [install options]

Roles:
  balancer, app, push, mysql-master, mysql-slave, opensearch

Environment:
  BITRIX_CLUSTER_REPO   Git repository URL (recommended)
  BITRIX_CLUSTER_REF    Branch or tag (default: main)
  BITRIX_CLUSTER_RAW    Raw URL base (alternative to git)
  BITRIX_CLUSTER_CACHE  Local cache dir (default: /var/cache/bitrix-cluster)

Examples:
  ./cluster/run.sh -c /etc/bitrix-cluster.env app -s -H app1 --with-transformer
  ./cluster/run.sh -r https://github.com/you/bitrix_al9.git mysql-master -s -M 'secret'
EOF
    exit "${1:-0}"
}

BITRIX_CLUSTER_REF="${BITRIX_CLUSTER_REF:-main}"
CLUSTER_ROLE=""
REMAINING_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r) BITRIX_CLUSTER_REPO="$2"; shift 2 ;;
        -b) BITRIX_CLUSTER_REF="$2"; shift 2 ;;
        -c)
            if [[ -f "$2" ]]; then
                # shellcheck disable=SC1090
                source "$2"
            fi
            shift 2
            ;;
        -h) usage 0 ;;
        -*)
            REMAINING_ARGS+=("$1")
            shift
            ;;
        *)
            CLUSTER_ROLE="$1"
            shift
            REMAINING_ARGS+=("$@")
            break
            ;;
    esac
done

[[ -n "${CLUSTER_ROLE}" ]] || usage 1

if [[ -f "${RUN_DIR}/../lib/cluster-fetch.sh" ]]; then
    # shellcheck disable=SC1091
    source "${RUN_DIR}/../lib/cluster-fetch.sh"
elif [[ -f "${BITRIX_CLUSTER_CACHE:-/var/cache/bitrix-cluster}/lib/cluster-fetch.sh" ]]; then
    # shellcheck disable=SC1091
    source "${BITRIX_CLUSTER_CACHE}/lib/cluster-fetch.sh"
else
    BITRIX_CLUSTER_CACHE="${BITRIX_CLUSTER_CACHE:-/var/cache/bitrix-cluster}"
    mkdir -p "${BITRIX_CLUSTER_CACHE}/lib"
    raw_base="${BITRIX_CLUSTER_RAW:-}"
    if [[ -z "${raw_base}" && -n "${BITRIX_CLUSTER_REPO:-}" ]]; then
        repo="${BITRIX_CLUSTER_REPO%.git}"
        repo="${repo#https://github.com/}"
        repo="${repo#git@github.com:}"
        raw_base="https://raw.githubusercontent.com/${repo}/${BITRIX_CLUSTER_REF}"
    fi
    [[ -n "${raw_base}" ]] || { echo "Set BITRIX_CLUSTER_REPO in -c env file or pass -r" >&2; exit 1; }
    curl -fsSL "${raw_base}/lib/cluster-fetch.sh" -o "${BITRIX_CLUSTER_CACHE}/lib/cluster-fetch.sh"
    curl -fsSL "${raw_base}/lib/cluster-install.sh" -o "${BITRIX_CLUSTER_CACHE}/lib/cluster-install.sh"
    # shellcheck disable=SC1091
    source "${BITRIX_CLUSTER_CACHE}/lib/cluster-fetch.sh"
fi

cluster_prepare_role "${CLUSTER_ROLE}" || exit 1

exec "${CLUSTER_SCRIPT_DIR}/install-${CLUSTER_ROLE}.sh" "${REMAINING_ARGS[@]}"
