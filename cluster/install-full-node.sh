#!/usr/bin/bash
#
# Full node: all Bitrix Environment 9 components on a single VM
# (app + MySQL + push + OpenSearch, optional transformer)
#
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/cluster-install.sh"
cluster_install_begin full-node "${BASH_SOURCE[0]}" "$@"

WITH_TRANSFORMER=0
HOSTIDENT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -H) HOSTIDENT="$2"; shift 2 ;;
        -M) MYPASSWORD="$2"; MYSQL_ROOT_PASSWORD="$2"; shift 2 ;;
        -m) MYSQL_VERSION="$2"; shift 2 ;;
        -G) PGSQL_PASSWORD="$2"; shift 2 ;;
        -g) PGSQL_VERSION="$2"; shift 2 ;;
        --with-transformer) WITH_TRANSFORMER=1; shift ;;
        -h)
            cat <<'EOF'
Usage: install-full-node.sh [-h] [-s] [-c cluster.env] [-H hostname]
       [-M mysql_root_password] [-m 8.0|8.4] [-G pgsql_password] [-g pgsql_version]
       [--with-transformer]

Installs Bitrix Environment 9 on a single VM: nginx, PHP-FPM, memcached,
Percona MySQL, PostgreSQL, push server, OpenSearch; optionally transformer stack.
EOF
            exit 0
            ;;
        *) shift ;;
    esac
done

[[ -n "${HOSTIDENT}" ]] && hostnamectl set-hostname "${HOSTIDENT}"

cluster_apply_full_node_defaults

MYPASSWORD=${MYPASSWORD:-${MYSQL_ROOT_PASSWORD:-}}
MYSQL_SERVER_ID=${MYSQL_SERVER_ID:-1}

run_role_base
pre_php
run_role_bitrix_repo
configure_python
configure_httpd
configure_php
configure_catdoc
configure_percona
configure_nodejs
configure_redis
configure_postgresql
prepare_percona_install
configure_push_server
install_percona
configure_bitrix_env
install_additional_packages
configure_memcached
configure_bitrix_nginx_php_fpm

if [[ ${WITH_TRANSFORMER} -eq 1 ]] || [[ "${TRANSFORMER_ENABLED:-0}" == "1" ]]; then
    configure_transformer
    if [[ -f "${CLUSTER_TEMPLATES_DIR}/transformer/transformer.env.tpl" ]]; then
        local_tpl="${CLUSTER_TEMPLATES_DIR}/transformer/transformer.env.tpl"
        content=$(cat "${local_tpl}")
        content=${content//@SITE_NAME@/${SITE_NAME:-default}}
        content=${content//@RABBITMQ_USER@/${RABBITMQ_USER:-transformer}}
        content=${content//@RABBITMQ_PASSWORD@/${RABBITMQ_PASSWORD:-}}
        content=${content//@RABBITMQ_VHOST@/${RABBITMQ_VHOST:-bitrix}}
        printf '%s\n' "${content}" > /etc/bitrix-transformer.env
        chmod 600 /etc/bitrix-transformer.env
    fi
fi

# OpenSearch single-node
configure_epel
OPENSEARCH_RPM="https://artifacts.opensearch.org/releases/bundle/opensearch/2/opensearch-2.15.0-linux-x64.rpm"
if ! rpm -qa | grep -q opensearch; then
    print "Installing OpenSearch. Please wait." 1
    dnf -y install "${OPENSEARCH_RPM}" >> ${LOGS_FILE} 2>&1 || \
        dnf -y install opensearch >> ${LOGS_FILE} 2>&1 || print_e "OpenSearch install failed"
fi

OPENSEARCH_CONF=/etc/opensearch/opensearch.yml
if [[ -f "${CLUSTER_TEMPLATES_DIR}/opensearch.yml.tpl" ]]; then
    cluster_render_template "${CLUSTER_TEMPLATES_DIR}/opensearch.yml.tpl" "${OPENSEARCH_CONF}.new"
    cp -a "${OPENSEARCH_CONF}" "${OPENSEARCH_CONF}.bak" 2>/dev/null || true
    cat "${OPENSEARCH_CONF}.new" >> "${OPENSEARCH_CONF}"
    rm -f "${OPENSEARCH_CONF}.new"
fi

HEAP=${OPENSEARCH_HEAP_SIZE:-1g}
mkdir -p /etc/opensearch/jvm.options.d
echo "-Xms${HEAP}" > /etc/opensearch/jvm.options.d/heap.options
echo "-Xmx${HEAP}" >> /etc/opensearch/jvm.options.d/heap.options
chown -R opensearch:opensearch /etc/opensearch /var/lib/opensearch 2>/dev/null || true

prepare_ansible_config
install_community_general_ansible_collection
install_community_mysql_ansible_collection
install_community_pgsql_ansible_collection
install_community_rabbitmq_ansible_collection
install_posix_ansible_collection

. /opt/webdir/bin/bitrix_utils.sh || exit 1

configure_mysql_passwords
configure_postgresql_password
update_crypto_key
configure_firewall_daemon "${CONFIGURE_IPTABLES}" "${CONFIGURE_FIREWALLD}"
configure_firewall_daemon_rtn=$?

if [[ ${configure_firewall_daemon_rtn} -eq 255 ]]; then
    print_e "$MBE0080"
elif [[ ${configure_firewall_daemon_rtn} -gt 0 ]]; then
    print_e "$MBE0081 ${LOGS_FILE}"
fi

remove_cockpit_from_firewalld

WS_HOST=${WS_HOST:-$(hostname -I | awk '{print $1}')}
configure_push_server_runtime

systemctl daemon-reload >> ${LOGS_FILE} 2>&1
systemctl enable memcached redis mysqld postgresql opensearch push-server >> ${LOGS_FILE} 2>&1
bitrix_enable_web_services
systemctl restart memcached redis mysqld postgresql opensearch >> ${LOGS_FILE} 2>&1

if [[ ${WITH_TRANSFORMER} -eq 1 ]] || [[ "${TRANSFORMER_ENABLED:-0}" == "1" ]]; then
    configure_firewall_ports 5672/tcp
fi

enable_dnf_makecache
print "Full node installed on $(hostname -s). All services run locally." 3
print "MySQL: localhost | Push WS_HOST=${WS_HOST} | OpenSearch: https://${OPENSEARCH_BIND_HOST:-localhost}:${OPENSEARCH_PORT:-9200}" 1
print "Copy SECURITY_KEY from /etc/sysconfig/push-server-multi to Push&Pull module." 1
[[ ${WITH_TRANSFORMER} -eq 1 ]] && print "Transformer config: /etc/bitrix-transformer.env" 1
[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}
exit 0
