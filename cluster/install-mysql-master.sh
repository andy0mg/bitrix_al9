#!/usr/bin/bash
#
# MySQL master: Percona Server + replication prep
#
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/cluster-install.sh"
cluster_install_begin mysql-master "${BASH_SOURCE[0]}" "$@"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -M) MYPASSWORD="$2"; MYSQL_ROOT_PASSWORD="$2"; shift 2 ;;
        -m) MYSQL_VERSION="$2"; shift 2 ;;
        -h) cluster_usage 0 ;;
        *) shift ;;
    esac
done

MYPASSWORD=${MYPASSWORD:-${MYSQL_ROOT_PASSWORD:-}}

MYSQL_SERVER_ID=${MYSQL_SERVER_ID:-1}

run_role_base
configure_percona
prepare_percona_install
install_percona
install_additional_packages
configure_mysql_root_password_simple

tpl="${CLUSTER_TEMPLATES_DIR}/mysql-master.cnf.d/replication.cnf"
if [[ -f "${tpl}" ]]; then
    sed "s/@SERVER_ID@/${MYSQL_SERVER_ID}/g" "${tpl}" > /etc/my.cnf.d/99-replication.cnf
    systemctl restart mysqld >> ${LOGS_FILE} 2>&1
fi

REPL_USER=${REPL_USER:-repl}
REPL_PASSWORD=${REPL_PASSWORD:-}
if [[ -n "${REPL_PASSWORD}" ]]; then
    mysql -e "CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED BY '${REPL_PASSWORD}';" >> ${LOGS_FILE} 2>&1
    mysql -e "GRANT REPLICATION SLAVE ON *.* TO '${REPL_USER}'@'%';" >> ${LOGS_FILE} 2>&1
    mysql -e "FLUSH PRIVILEGES;" >> ${LOGS_FILE} 2>&1
fi

configure_firewall_ports 3306/tcp
enable_dnf_makecache
print "MySQL master role installed. server-id=${MYSQL_SERVER_ID}" 3
[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}
exit 0
