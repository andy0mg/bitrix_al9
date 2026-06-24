#!/usr/bin/bash
#
# Push server: nodejs + redis + bx-push-server
#
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/cluster-install.sh"
cluster_install_begin push "${BASH_SOURCE[0]}" "$@"

HOSTIDENT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -H) HOSTIDENT="$2"; shift 2 ;;
        -h) cluster_usage 0 ;;
        *) shift ;;
    esac
done

[[ -n "${HOSTIDENT}" ]] && hostnamectl set-hostname "${HOSTIDENT}"

run_role_base
run_role_bitrix_repo
configure_nodejs
configure_redis
configure_push_server

systemctl enable redis >> ${LOGS_FILE} 2>&1
systemctl start redis >> ${LOGS_FILE} 2>&1

WS_HOST=${WS_HOST:-$(hostname -I | awk '{print $1}')}
configure_push_server_runtime

configure_firewall_ports 8010-8015/tcp 9010-9011/tcp 8893/tcp 8894/tcp

enable_dnf_makecache
print "Push server role installed. WS_HOST=${WS_HOST}" 3
print "Copy SECURITY_KEY from /etc/sysconfig/push-server-multi to Push&Pull module." 1
[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}
exit 0
