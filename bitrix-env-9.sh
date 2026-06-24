#!/usr/bin/bash
#
CLEANER=$1
#
if [[ ${CLEANER} == 'clean' ]]
then
    systemctl stop mysqld.service
    systemctl stop postgresql.service
    systemctl stop httpd.service
    systemctl stop nginx.service
    rm -f /etc/yum.repos.d/bitrix-9.repo
    dnf remove bitrix-env bx-ansible-core bx-nginx bx-push-server bx-catdoc bx-sphinx bx-mod_auth_ntlm_winbind -y
    dnf remove percona-server-* nodejs npm redis httpd* -y
    dnf remove postgresql postgresql-* -y
    dnf remove php php-common php-cli php-gd php-mbstring php-mcrypt php-mysqlnd php-ldap php-pspell php-pecl-xdebug php-pecl-geoip php-pecl-zip php-xml php-pear php-pecl-memcache php-pecl-rrd php-pecl-xhprof php-mysqli php-pgsql php-pecl-zendopcache php-pecl-apcu -y
    dnf remove remi-release epel-release -y
    dnf remove percona-release -y
    rm -f /etc/yum.repos.d/percona-original-release.repo.bak
    rm -f /etc/yum.repos.d/percona-prel-release.repo.bak
    rm -f /etc/yum.repos.d/percona-ps-80-release.repo.bak
    rm -f /etc/yum.repos.d/percona-tools-release.repo.bak
    rm -f /etc/yum.repos.d/nodesource-nodejs.repo
    rm -f /etc/yum.repos.d/nodesource-nsolid.repo
    rm -f /etc/yum.repos.d/remi.repo.rpmnew
    rm -f /etc/yum.repos.d/remi.repo.rpmsave
    rm -rf /etc/httpd
    rm -rf /etc/mysql
    rm -rf /etc/my.cnf.d
    rm -rf /etc/postgresql-setup
    rm -rf /etc/nginx
    rm -rf /etc/php.d
    rm -rf /etc/push-server
    rm -rf /etc/redis
    rm -f /etc/sysconfig/httpd
    rm -f /etc/logrotate.d/httpd
    rm -f /etc/logrotate.d/msmtp
    rm -f /etc/logrotate.d/redis
    rm -f /etc/my.cnf*
    rm -f /etc/php.ini*
    rm -rf /tmp/php_sessions
    rm -rf /tmp/php_upload
    rm -f /tmp/MYSQL_INIT*
    rm -rf /opt/push-server
    rm -rf /opt/webdir
    rm -rf /home/bitrix/.bx_temp
    rm -rf /home/bitrix/www
    rm -rf /var/www
    rm -rf /var/log/httpd
    rm -rf /var/log/nginx
    rm -rf /var/log/php
    rm -rf /var/log/redis
    rm -rf /var/log/push-server
    rm -f /var/log/mysqld.log
    rm -f /var/log/mysql.log
    rm -rf /var/lib/httpd
    rm -rf /var/lib/mysql
    rm -rf /var/lib/mysqld
    rm -rf /var/lib/mysql-files
    rm -rf /var/lib/mysql-keyring
    rm -rf /var/lib/pgsql
    rm -rf /var/lib/php
    rm -rf /var/lib/redis
    rm -f /root/.my.cnf*
    rm -f /root/.pgpass*
    rm -f /etc/tmpfiles.d/bvat.conf
    rm -f /etc/tmpfiles.d/mysqld.conf
    rm -rf /root/.ansible/collections/ansible_collections/community
    rm -rf /etc/ansible
    rm -f /etc/logrotate.d/mysql
    userdel -r bitrix
    userdel -r redis
    userdel -r nginx
    userdel -r apache
    userdel -r mysql
    userdel -r postgres
    groupdel bitrix
    groupdel redis
    groupdel nginx
    groupdel apache
    groupdel mysql
    groupdel postgres
    dnf clean all
    exit 0
fi
#
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/bitrix-common.sh"

BX_NAME=$(basename "$0" | sed -e "s/\.sh$//")
bitrix_init_defaults
bitrix_detect_os
bitrix_env_vars
bitrix_validate_os

while getopts ":H:M:m:G:g:spPth" OPT; do
    case ${OPT} in
        "H") HOSTIDENT="${OPTARG}" ;;
        "M") MYPASSWORD="${OPTARG}" ;;
        "m") MYSQL_VERSION="${OPTARG}" ;;
        "G") PGSQL_PASSWORD="${OPTARG}" ;;
        "g") PGSQL_VERSION="${OPTARG}" ;;
        "s") SILENT=1 ;;
        "p") POOL=1 ;;
        "P") PUSH=1 ;;
        "t") TEST_REPOSITORY=1 ;;
        "h") help_message ;;
        *)  help_message ;;
    esac
done

check_pool_and_push_options

if [[ ${SILENT} -eq 0 ]];
then
    print "====================================================================" 2
    print "$MBE0071" 2
    print "$MBE0072" 2
    print "$MBE0073" 2
    print "$MBE0074" 2
    print "====================================================================" 2
    ASK_USER=1
else
    ASK_USER=0
fi

show_os_and_version
remove_cockpit
configure_locale
disable_selinux
configure_exclude
disable_dnf_makecache
dnf_update
configure_dnf
configure_epel
configure_remi
configure_crb
disable_repos
configure_rsyslog_and_logrotate
configure_general
pre_php
configure_percona
configure_nodejs
configure_redis
configure_postgresql
prepare_percona_install
configure_bitrix_repo
dnf_update
configure_python
configure_httpd
configure_php
configure_catdoc
configure_push_server
install_percona
configure_bitrix_env
install_additional_packages
prepare_ansible_config
install_community_general_ansible_collection
install_community_mysql_ansible_collection
install_community_pgsql_ansible_collection
install_community_rabbitmq_ansible_collection
install_posix_ansible_collection
enable_dnf_makecache

. /opt/webdir/bin/bitrix_utils.sh || exit 1

configure_mysql_passwords
configure_postgresql_password
update_crypto_key
configure_firewall_daemon "${CONFIGURE_IPTABLES}" "${CONFIGURE_FIREWALLD}"
configure_firewall_daemon_rtn=$?

if [[ ${configure_firewall_daemon_rtn} -eq 255 ]];
then
    print_e "$MBE0080"
elif [[ ${configure_firewall_daemon_rtn} -gt 0 ]];
then
    print_e "$MBE0081 ${LOGS_FILE}"
fi

remove_cockpit_from_firewalld

print "$MBE0082" 1

if [[ ${POOL} -gt 0 ]];
then
    create_pool_on_install ${ASK_USER} "${BX_TYPE}" "${HOSTIDENT}" || print_e "$MBE0083 ${LOGS_FILE}"
    print "$MBE0084" 1
    awaiting_task_run 1
    if [[ ${PUSH} -gt 0 ]];
    then
        run_push_server_on_install ${ASK_USER} "${BX_TYPE}" "${HOSTIDENT}" || print_e "$MBE0090 ${LOGS_FILE}"
        print "$MBE0089" 1
        awaiting_task_run 2
    fi
fi

print "$MBE0112" 1

print "$MBE0085" 3

print "$MBE0113" 3

[[ ${TEST_REPOSITORY} -eq 0 ]] && rm -f ${LOGS_FILE}

exit 0
#
