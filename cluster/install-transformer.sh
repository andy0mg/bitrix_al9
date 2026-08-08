#!/usr/bin/bash
#
# Transformer role: RabbitMQ + LibreOffice + ffmpeg for Bitrix Document Converter
# (modules transformer + transformercontroller — Enterprise only, one node)
#
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/cluster-install.sh"
cluster_install_begin transformer "${BASH_SOURCE[0]}" "$@"

HOSTIDENT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -H) HOSTIDENT="$2"; shift 2 ;;
        -h)
            cat <<'EOF'
Usage: install-transformer.sh [-h] [-s] [-c cluster.env] [-H hostname]

Installs OS stack for Bitrix transformer / transformercontroller:
  erlang, rabbitmq-server, libreoffice-headless, ffmpeg
Writes credentials to /etc/bitrix-transformer.env
EOF
            exit 0
            ;;
        *) shift ;;
    esac
done

[[ -n "${HOSTIDENT}" ]] && hostnamectl set-hostname "${HOSTIDENT}"

run_role_base
configure_epel

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

enable_dnf_makecache
print "Transformer role installed. Config: /etc/bitrix-transformer.env" 3
print "Configure modules transformer + transformercontroller in Bitrix admin (Enterprise)." 1
[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}
exit 0
