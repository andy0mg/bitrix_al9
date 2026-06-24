#!/usr/bin/bash
#
# MySQL slave: Percona Server + replication to master
#
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/cluster-install.sh"
cluster_install_begin mysql-slave "${BASH_SOURCE[0]}" "$@"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -M) MYPASSWORD="$2"; MYSQL_ROOT_PASSWORD="$2"; shift 2 ;;
        -m) MYSQL_VERSION="$2"; shift 2 ;;
        -h) cluster_usage 0 ;;
        *) shift ;;
    esac
done

MYPASSWORD=${MYPASSWORD:-${MYSQL_ROOT_PASSWORD:-}}

MYSQL_SERVER_ID=${MYSQL_SERVER_ID:-2}
MASTER_HOST=${MASTER_HOST:-${MYSQL_MASTER:-}}
MASTER_PORT=${MASTER_PORT:-3306}

[[ -n "${MASTER_HOST}" ]] || print_e "MASTER_HOST or MYSQL_MASTER required in cluster.env"

run_role_base
configure_percona
prepare_percona_install
install_percona
install_additional_packages
configure_mysql_root_password_simple

tpl="${CLUSTER_TEMPLATES_DIR}/mysql-slave.cnf.d/replication.cnf"
if [[ -f "${tpl}" ]]; then
    sed "s/@SERVER_ID@/${MYSQL_SERVER_ID}/g" "${tpl}" > /etc/my.cnf.d/99-replication.cnf
    systemctl restart mysqld >> ${LOGS_FILE} 2>&1
fi

REPL_USER=${REPL_USER:-repl}
REPL_PASSWORD=${REPL_PASSWORD:-}
if [[ -n "${REPL_PASSWORD}" ]]; then
    mysql -e "STOP REPLICA;" >> ${LOGS_FILE} 2>&1 || true
    mysql -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='${MASTER_HOST}', SOURCE_PORT=${MASTER_PORT}, SOURCE_USER='${REPL_USER}', SOURCE_PASSWORD='${REPL_PASSWORD}', SOURCE_AUTO_POSITION=1;" >> ${LOGS_FILE} 2>&1
    mysql -e "START REPLICA;" >> ${LOGS_FILE} 2>&1
fi

configure_firewall_ports 3306/tcp
enable_dnf_makecache
print "MySQL slave role installed. Replicating from ${MASTER_HOST}:${MASTER_PORT}" 3
[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}
exit 0
