#!/usr/bin/bash
#
# OpenSearch single-node
#
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/cluster-install.sh"
cluster_install_begin opensearch "${BASH_SOURCE[0]}" "$@"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h) cluster_usage 0 ;;
        *) shift ;;
    esac
done

run_role_base
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
systemctl daemon-reload >> ${LOGS_FILE} 2>&1
systemctl enable opensearch >> ${LOGS_FILE} 2>&1
systemctl restart opensearch >> ${LOGS_FILE} 2>&1

configure_firewall_ports ${OPENSEARCH_PORT:-9200}/tcp
enable_dnf_makecache
print "OpenSearch single-node installed on port ${OPENSEARCH_PORT:-9200}" 3
print "Configure Search module in Bitrix admin: https://${OPENSEARCH_BIND_HOST:-localhost}:${OPENSEARCH_PORT:-9200}" 1
[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}
exit 0
