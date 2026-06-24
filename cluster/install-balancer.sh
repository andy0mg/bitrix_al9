#!/usr/bin/bash
#
# Load balancer: nginx (bx-nginx) + keepalived
#
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/cluster-install.sh"
cluster_install_begin balancer "${BASH_SOURCE[0]}" "$@"

HOSTIDENT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -H) HOSTIDENT="$2"; shift 2 ;;
        -h) echo "Usage: $0 [-h] [-s] [-c cluster.env] [-H hostname]"; exit 0 ;;
        *) shift ;;
    esac
done

[[ -n "${HOSTIDENT}" ]] && hostnamectl set-hostname "${HOSTIDENT}"

run_role_base
run_role_bitrix_repo
configure_bx_nginx
dnf -y install keepalived >> ${LOGS_FILE} 2>&1

cluster_build_upstream_block
mkdir -p /etc/nginx/bx/site_enabled
cluster_render_template "${CLUSTER_TEMPLATES_DIR}/nginx-upstream.conf.tpl" /etc/nginx/bx/site_enabled/upstream.conf
cluster_render_template "${CLUSTER_TEMPLATES_DIR}/http_balancer.conf.tpl" /etc/nginx/bx/site_enabled/http_balancer.conf

if [[ -f /etc/keepalived/keepalived.conf ]]; then
    cp -a /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.bak
fi
cluster_render_template "${CLUSTER_TEMPLATES_DIR}/keepalived.conf.tpl" /etc/keepalived/keepalived.conf

nginx -t >> ${LOGS_FILE} 2>&1
systemctl enable keepalived nginx >> ${LOGS_FILE} 2>&1
systemctl restart nginx keepalived >> ${LOGS_FILE} 2>&1

configure_firewall_ports 80/tcp 443/tcp
firewall-cmd --permanent --add-protocol=vrrp >> ${LOGS_FILE} 2>&1 || true
firewall-cmd --reload >> ${LOGS_FILE} 2>&1

enable_dnf_makecache
print "Balancer role installed. VIP=${VIP:-not set}" 3
[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}
exit 0
