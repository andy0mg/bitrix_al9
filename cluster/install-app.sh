#!/usr/bin/bash
#
# Application server: nginx + httpd + php + memcached + optional transformer
#
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/cluster-install.sh"
cluster_install_begin app "${BASH_SOURCE[0]}" "$@"

WITH_TRANSFORMER=0
HOSTIDENT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -H) HOSTIDENT="$2"; shift 2 ;;
        --with-transformer) WITH_TRANSFORMER=1; shift ;;
        -h) echo "Usage: $0 [-h] [-s] [-c cluster.env] [-H hostname] [--with-transformer]"; exit 0 ;;
        *) shift ;;
    esac
done

[[ -n "${HOSTIDENT}" ]] && hostnamectl set-hostname "${HOSTIDENT}"

run_role_base
pre_php
run_role_bitrix_repo
configure_python
configure_httpd
configure_php
configure_catdoc
configure_bitrix_env
install_additional_packages
configure_memcached

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
    configure_firewall_ports 5672/tcp
fi

if [[ -f /opt/webdir/bin/bitrix_utils.sh ]]; then
    # shellcheck disable=SC1091
    . /opt/webdir/bin/bitrix_utils.sh
    update_crypto_key
    configure_firewall_daemon "${CONFIGURE_IPTABLES}" "${CONFIGURE_FIREWALLD}" || true
    remove_cockpit_from_firewalld
else
    configure_firewall_ports 80/tcp 443/tcp 8080/tcp ${MEMCACHED_PORT:-11211}/tcp
fi

systemctl enable httpd nginx memcached >> ${LOGS_FILE} 2>&1
systemctl restart httpd nginx memcached >> ${LOGS_FILE} 2>&1

enable_dnf_makecache
print "Application server role installed." 3
[[ ${WITH_TRANSFORMER} -eq 1 ]] && print "Transformer stack ready. Config: /etc/bitrix-transformer.env" 1
[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}
exit 0
