#!/usr/bin/bash
#
# Shared Bitrix Environment 9 functions for monolithic and cluster installs.
#
[[ -n "${BITRIX_COMMON_SOURCED:-}" ]] && return 0
BITRIX_COMMON_SOURCED=1

bitrix_detect_os() {
#
ROCKY_RELEASE_FILE=/etc/rocky-release
ALMA_RELEASE_FILE=/etc/almalinux-release
ORACLE_RELEASE_FILE=/etc/oracle-release
CENTOS_RELEASE_FILE=/etc/centos-release
if [ -f "${ROCKY_RELEASE_FILE}" ]; then
    OS1=$(awk '{print $1}' ${ROCKY_RELEASE_FILE} | xargs echo -n)
    OS2=$(awk '{print $2}' ${ROCKY_RELEASE_FILE} | xargs echo -n)
    OS=${OS1}' '${OS2}
    VERSION=$(awk '{print $4}' ${ROCKY_RELEASE_FILE} | awk -F'.' '{print $1}')
fi
if [ -f "${ALMA_RELEASE_FILE}" ]; then
    OS=$(awk '{print $1}' ${ALMA_RELEASE_FILE} | xargs echo -n)
    VERSION=$(awk '{print $3}' ${ALMA_RELEASE_FILE} | awk -F'.' '{print $1}')
fi
if [ -f "${ORACLE_RELEASE_FILE}" ]; then
    OS1=$(awk '{print $1}' ${ORACLE_RELEASE_FILE} | xargs echo -n)
    OS2=$(awk '{print $2}' ${ORACLE_RELEASE_FILE} | xargs echo -n)
    OS=${OS1}' '${OS2}
    VERSION=$(awk '{print $5}' ${ORACLE_RELEASE_FILE} | awk -F'.' '{print $1}')
fi
if [ -f "${CENTOS_RELEASE_FILE}" ]; then
    OS1=$(awk '{print $1}' ${CENTOS_RELEASE_FILE} | xargs echo -n)
    OS2=$(awk '{print $2}' ${CENTOS_RELEASE_FILE} | xargs echo -n)
    OS=${OS1}' '${OS2}
    VERSION=$(awk '{print $4}' ${CENTOS_RELEASE_FILE} | awk -F'.' '{print $1}')
fi
#
}

bitrix_init_defaults() {
#
REPOFILE9=/etc/yum.repos.d/bitrix-9.repo
MYSQL_CNF=$HOME/.my.cnf
PGSQL_PASS=$HOME/.pgpass
PGSQL_VERSION="13"
PGSQL_PASSWORD=""
DEFAULT_SITE=/home/bitrix/www
[[ -z ${POOL} ]] && POOL=0
[[ -z ${PUSH} ]] && PUSH=0
CONFIGURE_IPTABLES=0
CONFIGURE_FIREWALLD=1
MYSQL_VERSION="8.0"
[[ -z ${SILENT} ]] && SILENT=0
[[ -z ${TEST_REPOSITORY} ]] && TEST_REPOSITORY=0
BX_PACKAGE="bitrix-env"
BX_TYPE=general
BX_CATDOC_PACKAGE="bx-catdoc"
if [ -f ".dev" ]; then DEV_MODE=1; else DEV_MODE=0; fi
LOGS_FILE=${LOGS_FILE:-$(mktemp /tmp/bitrix-env-XXXXX.log)}
IS_X86_64=$(uname -p | grep -wc 'x86_64')
#
}

bitrix_validate_os() {
#
[[ ${IS_X86_64} -eq 0 ]] && print_e "$MBE0091"
[[ ${EUID} -ne 0 ]] && print_e "$MBE0069"
[[ ( ! -f "/etc/rocky-release" ) && ( ! -f "/etc/almalinux-release" ) && ( ! -f "/etc/oracle-release" ) && ( ! -f "/etc/centos-release" ) ]] && print_e "$MBE0092"
[[ ( ${OS} != "Rocky Linux" ) && ( ${OS} != "AlmaLinux" ) && ( ${OS} != "Oracle Linux" ) && ( ${OS} != "CentOS Stream" ) ]] && print_e "$MBE0070"
os_version
#
}

run_role_base() {
#
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
#
}

run_role_bitrix_repo() {
#
configure_bitrix_repo
dnf_update
#
}

configure_memcached() {
#
MEMCACHED_PORT=${MEMCACHED_PORT:-11211}
MEMCACHED_BIND=${MEMCACHED_BIND:-0.0.0.0}
print "Installing memcached. Please wait." 1
dnf module enable memcached:remi -y >> ${LOGS_FILE} 2>&1
dnf -y install memcached >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 memcached"
if [[ -f /etc/sysconfig/memcached ]]; then
    sed -i "s/^PORT=.*/PORT=${MEMCACHED_PORT}/" /etc/sysconfig/memcached
    sed -i "s/^OPTIONS=.*/OPTIONS=\"-l ${MEMCACHED_BIND}\"/" /etc/sysconfig/memcached
fi
systemctl enable memcached >> ${LOGS_FILE} 2>&1
systemctl restart memcached >> ${LOGS_FILE} 2>&1
print "Memcached has been configured." 1
#
}

configure_transformer() {
#
SITE_NAME=${SITE_NAME:-default}
RABBITMQ_USER=${RABBITMQ_USER:-transformer}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD:-$(openssl rand -base64 24 2>/dev/null || echo "ChangeMe123")}
RABBITMQ_VHOST=${RABBITMQ_VHOST:-bitrix}
print "Installing transformer/transformercontroller dependencies. Please wait." 1
dnf -y install erlang rabbitmq-server libreoffice-headless ffmpeg >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 transformer-packages"
systemctl enable rabbitmq-server >> ${LOGS_FILE} 2>&1
systemctl start rabbitmq-server >> ${LOGS_FILE} 2>&1
rabbitmqctl add_vhost "${RABBITMQ_VHOST}" >> ${LOGS_FILE} 2>&1 || true
rabbitmqctl add_user "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}" >> ${LOGS_FILE} 2>&1 || true
rabbitmqctl set_permissions -p "${RABBITMQ_VHOST}" "${RABBITMQ_USER}" ".*" ".*" ".*" >> ${LOGS_FILE} 2>&1 || true
rabbitmqctl set_user_tags "${RABBITMQ_USER}" administrator >> ${LOGS_FILE} 2>&1 || true
TRANSFORMER_ENV="/etc/bitrix-transformer.env"
cat > "${TRANSFORMER_ENV}" <<EOF
# Post-install: configure Bitrix modules transformer + transformercontroller for site ${SITE_NAME}
SITE_NAME=${SITE_NAME}
RABBITMQ_HOST=127.0.0.1
RABBITMQ_PORT=5672
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
RABBITMQ_VHOST=${RABBITMQ_VHOST}
EOF
chmod 600 "${TRANSFORMER_ENV}"
print "Transformer OS stack configured. See ${TRANSFORMER_ENV}" 1
#
}

configure_firewall_ports() {
#
local ports=("$@")
if ! systemctl is-active firewalld >> ${LOGS_FILE} 2>&1; then
    systemctl enable --now firewalld >> ${LOGS_FILE} 2>&1
fi
for port in "${ports[@]}"; do
    firewall-cmd --permanent --add-port="${port}" >> ${LOGS_FILE} 2>&1 || true
done
firewall-cmd --reload >> ${LOGS_FILE} 2>&1
remove_cockpit_from_firewalld
#
}

configure_bx_nginx() {
#
print "Installing bx-nginx package. Please wait." 1
dnf -y install bx-nginx >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 bx-nginx"
systemctl enable nginx >> ${LOGS_FILE} 2>&1
systemctl start nginx >> ${LOGS_FILE} 2>&1
#
}

configure_mysql_replication_master() {
#
local cnf_dir="/etc/my.cnf.d"
local tpl_dir="${CLUSTER_TEMPLATES_DIR}/mysql-master.cnf.d"
mkdir -p "${cnf_dir}"
if [[ -f "${tpl_dir}/replication.cnf" ]]; then
    envsubst < "${tpl_dir}/replication.cnf" > "${cnf_dir}/99-replication.cnf" 2>/dev/null || \
    sed "s/@SERVER_ID@/${MYSQL_SERVER_ID:-1}/g" "${tpl_dir}/replication.cnf" > "${cnf_dir}/99-replication.cnf"
fi
systemctl restart mysqld >> ${LOGS_FILE} 2>&1
local repl_user="${REPL_USER:-repl}"
local repl_pass="${REPL_PASSWORD:?REPL_PASSWORD required}"
mysql -e "CREATE USER IF NOT EXISTS '${repl_user}'@'%' IDENTIFIED BY '${repl_pass}';" >> ${LOGS_FILE} 2>&1
mysql -e "GRANT REPLICATION SLAVE ON *.* TO '${repl_user}'@'%';" >> ${LOGS_FILE} 2>&1
mysql -e "FLUSH PRIVILEGES;" >> ${LOGS_FILE} 2>&1
print "MySQL master replication configured." 1
#
}

configure_mysql_replication_slave() {
#
local cnf_dir="/etc/my.cnf.d"
local tpl_dir="${CLUSTER_TEMPLATES_DIR}/mysql-slave.cnf.d"
mkdir -p "${cnf_dir}"
if [[ -f "${tpl_dir}/replication.cnf" ]]; then
    sed "s/@SERVER_ID@/${MYSQL_SERVER_ID:-2}/g" "${tpl_dir}/replication.cnf" > "${cnf_dir}/99-replication.cnf"
fi
systemctl restart mysqld >> ${LOGS_FILE} 2>&1
local master_host="${MASTER_HOST:?MASTER_HOST required}"
local master_port="${MASTER_PORT:-3306}"
local repl_user="${REPL_USER:-repl}"
local repl_pass="${REPL_PASSWORD:?REPL_PASSWORD required}"
mysql -e "STOP REPLICA;" >> ${LOGS_FILE} 2>&1 || true
mysql -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='${master_host}', SOURCE_PORT=${master_port}, SOURCE_USER='${repl_user}', SOURCE_PASSWORD='${repl_pass}', SOURCE_AUTO_POSITION=1;" >> ${LOGS_FILE} 2>&1
mysql -e "START REPLICA;" >> ${LOGS_FILE} 2>&1
print "MySQL slave replication configured." 1
#
}

configure_push_server_runtime() {
#
WS_HOST=${WS_HOST:-$(hostname -I | awk '{print $1}')}
SYSCONFIG=/etc/sysconfig/push-server-multi
if [[ -f "${SYSCONFIG}" ]]; then
    if grep -q '^WS_HOST=' "${SYSCONFIG}"; then
        sed -i "s/^WS_HOST=.*/WS_HOST=${WS_HOST}/" "${SYSCONFIG}"
    else
        echo "WS_HOST=${WS_HOST}" >> "${SYSCONFIG}"
    fi
fi
if [[ -x /etc/init.d/push-server-multi ]]; then
    /etc/init.d/push-server-multi reset >> ${LOGS_FILE} 2>&1
fi
systemctl enable push-server >> ${LOGS_FILE} 2>&1
systemctl start push-server >> ${LOGS_FILE} 2>&1
print "Push server runtime configured. WS_HOST=${WS_HOST}" 1
if [[ -f /etc/sysconfig/push-server-multi ]]; then
    grep SECURITY_KEY /etc/sysconfig/push-server-multi >> ${LOGS_FILE} 2>&1 || true
    print "SECURITY_KEY is in ${SYSCONFIG} and generated push-server json configs." 1
fi
#
}

configure_mysql_root_password_simple() {
#
systemctl enable mysqld >> ${LOGS_FILE} 2>&1
systemctl start mysqld >> ${LOGS_FILE} 2>&1
[[ -n "${MYPASSWORD:-}" ]] || return 0
local temp_pw
temp_pw=$(grep 'temporary password' /var/log/mysqld.log 2>/dev/null | tail -1 | awk '{print $NF}')
if [[ -n "${temp_pw}" ]]; then
    mysql --connect-expired-password -uroot -p"${temp_pw}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYPASSWORD}';" >> ${LOGS_FILE} 2>&1
else
    mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYPASSWORD}';" >> ${LOGS_FILE} 2>&1 || true
fi
cat > "${MYSQL_CNF}" <<EOF
[client]
user=root
password="${MYPASSWORD}"
EOF
chmod 600 "${MYSQL_CNF}"
print "MySQL root password configured." 1
#
}

bitrix_env_vars() {
#
MBE0001="Log file path: "
MBE0002="Create management pool after installing $BX_PACKAGE package"
MBE0003="Use silent mode (don't query for information)"
MBE0004="Set server name for management pool creation procedure"
MBE0005="Set root user password for MySQL service"
MBE0006="Use alpha/test version of Bitrix Environment"
MBE0007="Use iptables as firewall service daemon (default for Centos 6)"
MBE0008="Use firewalld as firewall service daemon (default for Centos 7 system)"
MBE0009="Examples:"
MBE0010="install $BX_PACKAGE package and configure management pool:"
MBE0011="install $BX_PACKAGE package, configure management pool, set mysql root password and version 8.0:"
MBE0120="install $BX_PACKAGE package, configure management pool, run push server,"
MBE0121="set mysql root password1 and mysql version 8.4,"
MBE0122="set postgresql postgres password2 and postgresql version 16:"
MBE0123="Print help message"
MBE0124="Usage:"
#
MBE0012="You have to disable SElinux before installing Bitrix Environment."
MBE0013="You have to reboot the server to disable SELinux"
MBE0014="Do you want to disable SELinux?(Y|n)"
MBE0015="SELinux status changed to disabled in the config file"
MBE0016="Please reboot the system! (cmd: reboot)"
#
MBE0017="EPEL repository is already configured on the server."
MBE0018="Getting EPEL repository configuration. Please wait."
MBE0019="Error importing the GPG key:"
MBE0020="Error installing the rpm-package:"
MBE0021="EPEL repository has been configured successfully."
#
MBE0022="Enable main REMI repository. Please wait."
MBE0023="Disable php 5.6 repository. Please wait."
MBE0024="Disable php 7.0 repository. Please wait."
MBE0025="Disable php 7.1 repository. Please wait."
MBE00251="Disable php 7.2 repository. Please wait."
MBE00252="Disable php 7.3 repository. Please wait."
MBE00253="Disable php 7.4 repository. Please wait."
MBE00254="Disable php 8.0 repository. Please wait."
MBE00255="Disable php 8.1 repository. Please wait."
MBE00256="Enable php 8.2 repository. Please wait."
MBE00257="Disable php 8.3 repository. Please wait."
MBE00258="Disable php 8.4 repository. Please wait."
MBE00259="Disable php 8.5 repository. Please wait."
#
MBE0261="Create management pool after installing $BX_PACKAGE package"
MBE0262="Run push server after installing $BX_PACKAGE package and create management pool"
MBE0263="Create management pool before run push server. Exit."
#
MBE0026="REMI repository is already configured on the server."
MBE0027="Getting REMI repository configuration. Please wait."
MBE0028="Error importing the GPG key:"
MBE0029="Error installing the rpm-package:"
MBE0030="REMI repository has been configured successfully."
#
MBE0031="Percona repository is already configured on the server."
MBE0032="Error installing the rpm-package:"
MBE0033="Percona repository configuration has been completed."
MBE0034="MariaDB server has been detected. Skipping mariadb-libs uninstallation."
MBE0035="mariadb-libs package has been uninstalled."
MBE0036="MySQL server has been detected. Skipping mysql-libs uninstallation."
MBE0037="mysql-libs package has been uninstalled."
#
MBE0038="Bitrix repository is already configured on the server."
MBE0039="Getting Bitrix repository configuration. Please wait."
MBE0040="Error importing the GPG key:"
MBE0041="Bitrix repository has been configured."
#
MBE0042="System update in progress. Please wait."
MBE0043="Error updating the system."
#
MBE0044="Maximum attempts to set the password has been reached. Exiting."
MBE0045="Enter root password:"
MBE0046="Re-enter root password:"
MBE0047="Sorry, passwords do not match! Please try again."
MBE0048="Sorry, password can't be empty."
MBE0049="MySQL password updated successfully."
MBE0050="MySQL password update failed."
MBE0051="mysql client config file updated:"
MBE0052="Updating MySQL service root password:"
MBE0053="Default mysql client config file not found:"
MBE0054="Empty mysql root password was found, but it does not work."
MBE0055="Temporary mysql root password was found, but it does not work."
MBE0056="Default mysql client config file was found: "
MBE0057="Do you want to update $MYSQL_CNF default config file?(Y|n): "
MBE0058="User has chosen silent mode. Cannot request correct MySQL password."
MBE0059="mysql client config file $MYSQL_CNF updated."
MBE0060="Empty mysql root password was found, you have to change it!"
MBE0061="Temporary mysql root password was found, you have to change it!"
MBE0062="Saved mysql root password was found, you have to change it!"
MBE0063="Saved mysql root password was found, but it does not work."
#
MBE0064="Do you want to change the root user password for MySQL service?(Y|n) "
MBE0065="Root mysql password test completed"
MBE0066="MySQL root user account has been updated while installing the MySQL service."
MBE0067="You can find MySQL password settings in config file: $MYSQL_CNF."
MBE0068="MySQL security configuration has been completed."
#
MBE0069="This script needs to be run as root to avoid errors."
MBE0070="This script has been tested only on Rocky Linux, Alma Linux, Oracle Linux, CentOS Stream. Current OS: ${OS}"
#
MBE0071="Bitrix Environment for Linux installation script."
MBE0072="Yes will be assumed as a default answer."
MBE0073="Enter 'n' or 'no' for a 'No'. Anything else will be considered a 'Yes'."
MBE0074="This script MUST be run as root, or it will fail."
MBE0075="The script does not support CentOS"
MBE0076="Installing php packages. Please wait."
MBE0077="Installing $BX_PACKAGE package. Please wait."
MBE0078="Installing bx-push-server package. Please wait."
MBE0079="Error installing package:"
MBE0080="iptables modules are disabled in the system. Nothing to do."
MBE0081="Cannot configure firewall on the server. Log file:"
MBE0082="Firewall has been configured."
MBE0083="Cannot create management pool. Log file: "
MBE0084="Management pool has been configured. Please wait."
MBE0085="Bitrix Environment $BX_PACKAGE has been installed successfully."
#MBE0086="Select MySQL version: 5.7 or 8.0 (Version 5.7 is default).
#              The option is not working on CentOS 6."
MBE0086="Set MySQL Percona Server version: 8.0 or 8.4 (version 8.0 is default)"
MBE0087="There is no support Percona Server 8.0 for Centos 6. Exit."
MBE0088="Installing python 3.11 packages. Please wait."
MBE0089="Push server has been configured. Please wait."
MBE0090="Cannot run push server. Log file: "
#
MBE0091="This script run only on x86_64 architecture."
MBE0092="Check for Rocky Linux or for Alma Linux or for Oracle Linux or for CentOS Stream failed."
MBE0093="OS and version:"
#
MBE0101="NodeJS repository configuration has been completed."
MBE0102="NodeJS repository is already configured on the server."
MBE0103="Installing redis package. Please wait."
MBE0104="Disable repositories. Please wait."
MBE0105="Redis is already installed on the server."
MBE0106="Percona Server is already installed on the server."
#
MBEPG01="Set PostgreSQL version: 15 or 16 (version 13 is default)"
MBEPG02="Set postgres user password for PostgreSQL service"
MBEPG03="PostgreSQL version must be 15 or 16. Exit."
MBEPG04="PostgreSQL packages are already installed on the server."
MBEPG05="Installing postgresql packages. Please wait."
MBEPG06="Failed to create .pgpass file"
MBEPG07="Failed to set PostgreSQL password"
MBEPG08="Failed to update PostgreSQL configuration"
MBEPG09="Failed to connect to PostgreSQL with new password"
MBEPG10="PostgreSQL security configuration has been completed."
MBEPG11="PostgreSQL postgres user account has been updated while installing the PostgreSQL service."
MBEPG12="You can find PostgreSQL password settings in config file: $PGSQL_PASS."
#
MBE0107="CRB repository has been configured successfully."
MBE0108="Installing $BX_CATDOC_PACKAGE package. Please wait."
MBE0109="Installing httpd packages. Please wait."
#
MBE0110="Wait for pool create task take cycles: "
MBE0111="Wait for run push server task take cycles: "
MBE0112="Please wait until all tasks is finished."
MBE0113="Good luck)"
#
}

print() {
#
    MSG=$1
    NOTICE=${2:-0}
    [[ ( ${SILENT} -eq 0 ) && ( ${NOTICE} -eq 1 ) ]] && echo -e "${MSG}"
    [[ ( ${SILENT} -eq 0 ) && ( ${NOTICE} -eq 2 ) ]] && echo -e "\e[1;31m${MSG}\e[0m"
    [[ ( ${SILENT} -eq 0 ) && ( ${NOTICE} -eq 3 ) ]] && echo -e "\e[1;32m${MSG}\e[0m"
    echo "$(date +"%FT%H:%M:%S"): $$ : $MSG" >> ${LOGS_FILE}
#
}

print_e() {
#
    MSG_E=$1
    print "$MSG_E" 2
    print "$MBE0001 ${LOGS_FILE}" 1
    exit 1
#
}

help_message() {
#
#         -I - $MBE0007
#         -F - $MBE0008
#         $0 -s -p -H master1
#         $0 -s -p -H master1 -M 'password' -m 8.0"
#    Usage: $0 [-h] [-s] [-t] [-p [-H hostname]] [-M mysql_root_password] [-m 5.7|8.0]
    echo "
    $MBE0124

         $0 [-h] [-s] [-p [-H hostname]] [-P] [-t] [-M mysql_root_password] [-m 8.0|8.4] [-G postgresql_postgres_password] [-g 15|16]

         -h - $MBE0123
         -s - $MBE0003
         -p - $MBE0261
         -H - $MBE0004
         -P - $MBE0262
         -t - $MBE0006
         -M - $MBE0005
         -m - $MBE0086
         -G - $MBEPG02
         -g - $MBEPG01

    $MBE0009

         * $MBE0010
         $0 -s -p -H server1

         * $MBE0011
         $0 -s -p -H server1 -M 'password' -m 8.0

         * $MBE0120
         * $MBE0121
         * $MBE0122
         $0 -s -p -H server1 -P -M 'password1' -m 8.4 -G 'password2' -g 16
    "
    exit
#
}

remove_cockpit() {
#
    systemctl stop cockpit.service >> ${LOGS_FILE} 2>&1
    systemctl stop cockpit.socket >> ${LOGS_FILE} 2>&1
    systemctl disable cockpit.service >> ${LOGS_FILE} 2>&1
    systemctl disable cockpit.socket >> ${LOGS_FILE} 2>&1
    rpm -e cockpit-packagekit >> ${LOGS_FILE} 2>&1
    rpm -e cockpit-podman >> ${LOGS_FILE} 2>&1
    rpm -e cockpit-storaged >> ${LOGS_FILE} 2>&1
    rpm -e cockpit >> ${LOGS_FILE} 2>&1
    rpm -e cockpit-ws >> ${LOGS_FILE} 2>&1
    rpm -e cockpit-system >> ${LOGS_FILE} 2>&1
    rpm -e cockpit-bridge >> ${LOGS_FILE} 2>&1
    rm -rf /run/cockpit >> ${LOGS_FILE} 2>&1
    rm -rf /etc/cockpit >> ${LOGS_FILE} 2>&1
    rm -rf /usr/share/cockpit >> ${LOGS_FILE} 2>&1
#
}

remove_cockpit_from_firewalld() {
#
    firewall-cmd --permanent --remove-service=cockpit >> ${LOGS_FILE} 2>&1
    firewall-cmd --permanent --remove-port=9090/tcp >> ${LOGS_FILE} 2>&1
#
}

configure_locale() {
#
    # install package if not installed
    LANG_PACKS_PACKAGE='langpacks-en'
    LANG_PACKS=$(rpm -qa | grep -c '${LANG_PACKS_PACKAGE}')
    if [[ ${LANG_PACKS} -eq 0 ]];
    then
        dnf -y install ${LANG_PACKS_PACKAGE} >> ${LOGS_FILE} 2>&1
    fi
    # setup default locale
    DEFAULT_LOCALE='en_US.UTF-8'
    EN_LOCALE=$(localectl list-locales | grep -c ${DEFAULT_LOCALE})
    if [[ ${EN_LOCALE} -eq 1 ]];
    then
        localectl set-locale LANG=${DEFAULT_LOCALE} >> ${LOGS_FILE} 2>&1
    fi
#
}

disable_selinux() {
#
    SESTATUS_CMD=$(which sestatus 2> /dev/null)
    [[ -z ${SESTATUS_CMD} ]] && return 0

    SESTATUS=$(${SESTATUS_CMD} | awk -F':' '/SELinux status:/{print $2}' | sed -e "s/\s\+//g")
    SECONFIGS="/etc/selinux/config /etc/sysconfig/selinux"
    if [[ ${SESTATUS} != "disabled" ]];
    then
        print "$MBE0012" 1
        print "$MBE0013"
        read -r -p "$MBE0014 " DISABLE
        [[ -z ${DISABLE} ]] && DISABLE=y
        [[ $(echo ${DISABLE} | grep -wci "y") -eq 0 ]] && print_e "Exit."
        for SECONFIG in ${SECONFIGS}; do
            [[ -f ${SECONFIG} ]] && sed -i "s/SELINUX=\(enforcing\|permissive\)/SELINUX=disabled/" ${SECONFIG} && print "$MBE0015 ${SECONFIG}." 1
        done
        print "$MBE0016" 1
        exit
    fi
    # disable motd cocpit
    rm -f /etc/motd.d/cockpit
#
}

configure_epel() {
#
    EPEL=$(rpm -qa | grep -c 'epel-release')
    if [[ ${EPEL} -gt 0 ]];
    then
        print "$MBE0017" 1
        return 0
    fi
    print "$MBE0018" 1

#    if [[ $VER -eq 6 ]];
#    then
#        LINK="https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm"
#        GPGK="https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-6"
#    else
#        LINK="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
#        GPGK="https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7"
#    fi

    # banned from some locations...
    #LINK="https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
    #GPGK="https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9"

    # debian mirror
    LINK="https://cdimage.debian.org/mirror/fedora/epel/epel-release-latest-9.noarch.rpm"
    GPGK="https://cdimage.debian.org/mirror/fedora/epel/RPM-GPG-KEY-EPEL-9"

    rpm --import "${GPGK}" >> ${LOGS_FILE} 2>&1 || print_e "$MBE0019 ${GPGK}"
    rpm -Uvh "${LINK}" >> ${LOGS_FILE} 2>&1 || print_e "$MBE0020 ${LINK}"

    dnf clean all > /dev/null 2>&1
    #dnf install -y yum-fastestmirror > /dev/null 2>&1
    print "$MBE0021" 1
#
}

configure_remi() {
#
    REMI=$(rpm -qa | grep -c 'remi-release')
    if [[ ${REMI} -gt 0 ]];
    then
        print "$MBE0026" 1
        return 0
    fi
    print "$MBE0027" 1

#    if [[ $VER -eq 6 ]];
#    then
#        LINK="http://rpms.famillecollet.com/enterprise/remi-release-6.rpm"
#    else
#        LINK="http://rpms.famillecollet.com/enterprise/remi-release-7.rpm"
#    fi

    GPGK="http://rpms.famillecollet.com/RPM-GPG-KEY-remi"
    LINK="http://rpms.famillecollet.com/enterprise/remi-release-9.rpm"

    rpm --import "${GPGK}" >> ${LOGS_FILE} 2>&1 || print_e "$MBE0028 ${GPGK}"
    rpm -Uvh "${LINK}" >> ${LOGS_FILE} 2>&1 || print_e "$MBE0029 ${LINK}"
    print "$MBE0030" 1
#
}

configure_crb() {
#
    # enable Code Ready Builder repository
    if [[ ( ${OS} == 'Rocky Linux' ) || ( ${OS} == 'AlmaLinux' ) || ( ${OS} == 'CentOS Stream' ) ]];
    then
        dnf config-manager --set-enabled crb >> ${LOGS_FILE} 2>&1
    fi
    if [[ ${OS} == 'Oracle Linux' ]];
    then
        dnf -y install dnf-plugins-core >> ${LOGS_FILE} 2>&1
        dnf config-manager --enable ol9_codeready_builder >> ${LOGS_FILE} 2>&1
    fi
    print "$MBE0107" 1
#
}

pre_php() {
#
    print "$MBE0022" 1
    sed -i -e '/\[remi\]/,/^\[/s/enabled=0/enabled=1/' /etc/yum.repos.d/remi.repo
#
#    print "$MBE0023"
#    sed -i -e '/\[remi-php56\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi.repo
#
#    print "$MBE0024"
#    sed -i -e '/\[remi-php70\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi-php70.repo
#
#    print "$MBE0025"
#    sed -i -e '/\[remi-php71\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi-php71.repo
#
#    print "$MBE00251"
#    sed -i -e '/\[remi-php72\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi-php72.repo
#
#    print "$MBE00252"
#    sed -i -e '/\[remi-php73\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi-php73.repo

    print "$MBE00253" 1
#    sed -i -e '/\[remi-php74\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi-php74.repo
    dnf module disable php:remi-7.4 -y >> ${LOGS_FILE} 2>&1

    print "$MBE00254" 1
#    sed -i -e '/\[remi-php80\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi-php80.repo
    dnf module disable php:remi-8.0 -y >> ${LOGS_FILE} 2>&1

    print "$MBE00255" 1
#    sed -i -e '/\[remi-php81\]/,/^\[/s/enabled=0/enabled=1/' /etc/yum.repos.d/remi-php81.repo
    dnf module disable php:remi-8.1 -y >> ${LOGS_FILE} 2>&1

    print "$MBE00256" 1
    dnf module enable php:remi-8.2 -y >> ${LOGS_FILE} 2>&1

    print "$MBE00257" 1
    dnf module disable php:remi-8.3 -y >> ${LOGS_FILE} 2>&1

    print "$MBE00258" 1
    dnf module disable php:remi-8.4 -y >> ${LOGS_FILE} 2>&1

    print "$MBE00259" 1
    dnf module disable php:remi-8.5 -y >> ${LOGS_FILE} 2>&1

#    if [[ $is_xhprof -gt 0 ]];
#    then
#        dnf -y remove php-pecl-xhprof
#    fi
#
}

disable_repos() {
#
    print "$MBE0104" 1
    dnf module disable mariadb:10.11 -y >> ${LOGS_FILE} 2>&1
    if [[ ${OS} == 'CentOS Stream' ]];
    then
        dnf module disable mariadb:11.8 -y >> ${LOGS_FILE} 2>&1
    fi
    dnf module disable maven:3.8 -y >> ${LOGS_FILE} 2>&1
    dnf module disable maven:3.9 -y >> ${LOGS_FILE} 2>&1
    dnf module disable nginx:1.22 -y >> ${LOGS_FILE} 2>&1
    dnf module disable nginx:1.24 -y >> ${LOGS_FILE} 2>&1
    dnf module disable nginx:1.26 -y >> ${LOGS_FILE} 2>&1
    dnf module disable nodejs:18 -y >> ${LOGS_FILE} 2>&1
    dnf module disable nodejs:20 -y >> ${LOGS_FILE} 2>&1
    dnf module disable nodejs:22 -y >> ${LOGS_FILE} 2>&1
    dnf module disable nodejs:24 -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:8.1 -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:8.2 -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:8.3 -y >> ${LOGS_FILE} 2>&1
    dnf module disable mysql:8.4 -y >> ${LOGS_FILE} 2>&1
    dnf module disable postgresql:15 -y >> ${LOGS_FILE} 2>&1
    dnf module disable postgresql:16 -y >> ${LOGS_FILE} 2>&1
    dnf module disable redis:7 -y >> ${LOGS_FILE} 2>&1
    dnf module disable ruby:3.1 -y >> ${LOGS_FILE} 2>&1
    dnf module disable ruby:3.3 -y >> ${LOGS_FILE} 2>&1
    dnf module disable swig:4.1 -y >> ${LOGS_FILE} 2>&1
    dnf module disable swig:4.3 -y >> ${LOGS_FILE} 2>&1
    dnf module disable composer:2 -y >> ${LOGS_FILE} 2>&1
    dnf module disable memcached:remi -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:remi-7.4 -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:remi-8.0 -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:remi-8.1 -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:remi-8.3 -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:remi-8.4 -y >> ${LOGS_FILE} 2>&1
    dnf module disable php:remi-8.5 -y >> ${LOGS_FILE} 2>&1
    dnf module disable redis:remi-5.0 -y >> ${LOGS_FILE} 2>&1
    dnf module disable redis:remi-6.0 -y >> ${LOGS_FILE} 2>&1
    dnf module disable redis:remi-6.2 -y >> ${LOGS_FILE} 2>&1
    dnf module disable redis:remi-7.0 -y >> ${LOGS_FILE} 2>&1
    dnf module disable redis:remi-7.2 -y >> ${LOGS_FILE} 2>&1
    dnf module disable redis:remi-8.0 -y >> ${LOGS_FILE} 2>&1
    dnf module disable redis:remi-8.4 -y >> ${LOGS_FILE} 2>&1
    dnf module disable valkey:remi-8.1 -y >> ${LOGS_FILE} 2>&1
    dnf module disable valkey:remi-9.0 -y >> ${LOGS_FILE} 2>&1
#
}

configure_rsyslog_and_logrotate() {
#
    dnf -y install logrotate rsyslog rsyslog-gnutls rsyslog-gssapi rsyslog-logrotate rsyslog-relp >> ${LOGS_FILE} 2>&1
    systemctl restart rsyslog.service >> ${LOGS_FILE} 2>&1
    systemctl enable rsyslog.service >> ${LOGS_FILE} 2>&1
    systemctl restart logrotate.service >> ${LOGS_FILE} 2>&1
    systemctl enable logrotate.service >> ${LOGS_FILE} 2>&1
#
}

configure_general() {
#
    dnf -y install etckeeper psmisc mc htop bzip2 tar zip unzip unrar rsync curl wget vi vim nmap initscripts >> ${LOGS_FILE} 2>&1
#
}

configure_percona() {
#
    PERCONA=$(rpm -qa | grep -c 'percona-release')
    if [[ ${PERCONA} -gt 0 ]];
    then
        print "$MBE0031" 1
        return 0
    fi

    # rpm -Uvh "$LINK" >>${LOGS_FILE} 2>&1 || \
    # http://repo.percona.com/release/percona-release-latest.noarch.rpm
    LINK="https://repo.percona.com/yum/percona-release-latest.noarch.rpm"

    dnf -y install "${LINK}" >> ${LOGS_FILE} 2>&1 || print_e "$MBE0032 ${LINK}"

    # dnf -y --nogpg update percona-release >> ${LOGS_FILE} 2>&1
    which percona-release >> ${LOGS_FILE} 2>&1
    print "$MBE0033" 1

    # if [[ $MYVERSION == "8.0" || $MYVERSION == "80" ]];
    # then
    #     percona-release enable ps-80 release >> ${LOGS_FILE} 2>&1
    # else
    #     percona-release setup -y ps57 >> ${LOGS_FILE} 2>&1
    # fi

    if [[ ${MYSQL_VERSION} == "8.4" ]];
    then
        percona-release enable ps-84-lts release >> ${LOGS_FILE} 2>&1
        percona-release setup -y ps84-lts >> ${LOGS_FILE} 2>&1
    else
        percona-release enable ps-80 release >> ${LOGS_FILE} 2>&1
        percona-release setup -y ps80 >> ${LOGS_FILE} 2>&1
    fi
#
}

install_percona() {
#
    PERCONA_SERVER=$(rpm -qa | grep -c 'percona-server-server')
    if [[ ${PERCONA_SERVER} -gt 0 ]];
    then
        print "$MBE0106" 1
        return 0
    fi

    dnf -y install percona-server-server percona-server-client percona-server-shared percona-server-devel percona-icu-data-files >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 percona-server"
#
}

configure_nodejs() {
#
    NODEJS_VERSION=22
    NODEJS=$(rpm -qa | grep -c 'nodejs')
    if [[ ${NODEJS} -gt 0 ]];
    then
        print "$MBE0102" 1
        return 0
    fi

    if [[ ( ${OS} == 'Rocky Linux' ) || ( ${OS} == 'AlmaLinux' ) || ( ${OS} == 'CentOS Stream' ) ]];
    then
        APPSTREAM_NAME='appstream'
    fi
    if [[ ${OS} == 'Oracle Linux' ]];
    then
        APPSTREAM_NAME='ol9_appstream'
    fi

    # disable appstream to install npm from node repo
    dnf config-manager --set-disabled ${APPSTREAM_NAME}

    LINK="https://rpm.nodesource.com/setup_${NODEJS_VERSION}.x"

    curl --silent --location "${LINK}" | bash - > /dev/null 2>&1
    dnf -y install nodejs npm >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 nodejs"

    # enable appstream back
    dnf config-manager --set-enabled ${APPSTREAM_NAME}
    print "$MBE0101" 1
#
}

configure_redis() {
#
    REDIS_VERSION=8.2
    REDIS=$(rpm -qa | grep -c 'redis')
    if [[ ${REDIS} -gt 0 ]];
    then
        print "$MBE0105" 1
        return 0
    fi

    dnf module enable redis:remi-${REDIS_VERSION} -y >> ${LOGS_FILE} 2>&1
    dnf -y install redis >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 redis"
    print "$MBE0103" 1
#
}

configure_postgresql() {
#
    PGSQL=$(rpm -qa | grep -c 'postgresql-server')
    if [[ ${PGSQL} -gt 0 ]];
    then
        print "$MBEPG04" 1
        return 0
    fi

    if [[ ${PGSQL_VERSION} == "15" || ${PGSQL_VERSION} == "16" ]];
    then
        dnf module enable postgresql:${PGSQL_VERSION} -y >> ${LOGS_FILE} 2>&1
    fi
    dnf -y install postgresql-server postgresql postgresql-contrib >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 postgresql"
    postgresql-setup --initdb >> ${LOGS_FILE} 2>&1
    print "$MBEPG05" 1
#
}

configure_php() {
#
    PHP_VERSION=8.2
    print "$MBE0076" 1
    dnf module install php:remi-${PHP_VERSION} -y >> ${LOGS_FILE} 2>&1
    dnf -y install php php-mysqli php-pgsql php-pecl-apcu php-pecl-zendopcache php-pecl-redis6 php-pecl-msgpack php-pecl-igbinary >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 php-packages"
    # remove fpm because install as depends
    systemctl stop php-fpm.service >> ${LOGS_FILE} 2>&1
    systemctl disable php-fpm.service >> ${LOGS_FILE} 2>&1
    dnf remove -y php-fpm >> ${LOGS_FILE} 2>&1
#
}

configure_httpd() {
#
    print "$MBE0109" 1
    dnf -y install httpd httpd-core httpd-devel httpd-filesystem httpd-tools >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 httpd-packages"
#
}

configure_push_server() {
#
    print "$MBE0078" 1
    dnf -y install bx-push-server >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 bx-push-server"
#
}

configure_bitrix_env() {
#
    print "$MBE0077" 1
    dnf -y install ${BX_PACKAGE} >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 ${BX_PACKAGE}"
#
}

configure_python() {
#
    print "$MBE0088" 1
    PYTHON_311_PACKAGES="python3.11 python3.11-libs python3.11-pip-wheel python3.11-setuptools-wheel python3.11-PyMySQL python3.11-psycopg2"
    dnf -y install ${PYTHON_311_PACKAGES} >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 python 3.11 packages"
#
}

configure_catdoc() {
#
    print "$MBE0108" 1
    dnf -y install ${BX_CATDOC_PACKAGE} >> ${LOGS_FILE} 2>&1 || print_e "$MBE0079 ${BX_CATDOC_PACKAGE} package"
#
}

install_additional_packages() {
#
    dnf -y install perl-lib perl-Sys-Hostname perl-IO-Interface perl-DBI perl-DBD-Pg glibc-gconv-extra >> ${LOGS_FILE} 2>&1
    REPO_SOURCE_URL="https://repo.bitrix.info/sources/"
    # both packages conflicts in dnf install ..., cant resolve, just download and install directly on rpm
    if [[ ${OS} == 'Rocky Linux' ]];
    then
        # original source
        # https://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/Packages/m/mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm
        # https://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/Packages/p/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm
        # PACKAGES_LINK="https://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/Packages/"
        #
        # vmbitrix source
        # https://repo.bitrix.info/sources/rocky/mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm
        # https://repo.bitrix.info/sources/rocky/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm
        PACKAGES_LINK="${REPO_SOURCE_URL}rocky/"
        PACKAGE_CONNECTOR_C="mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm"
        PACKAGE_PERL_DBD_MYSQL="perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
    fi
    if [[ ${OS} == 'AlmaLinux' ]];
    then
        # original source
        # https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/Packages/mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm
        # https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/Packages/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm
        # PACKAGES_LINK="https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/Packages/"
        #
        # vmbitrix source
        # https://repo.bitrix.info/sources/alma/mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm
        # https://repo.bitrix.info/sources/alma/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm
        PACKAGES_LINK="${REPO_SOURCE_URL}alma/"
        PACKAGE_CONNECTOR_C="mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm"
        PACKAGE_PERL_DBD_MYSQL="perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
    fi
    if [[ ${OS} == 'Oracle Linux' ]];
    then
        # original source
        # https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64/getPackage/mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm
        # https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64/getPackage/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm
        # PACKAGES_LINK="https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64/getPackage/"
        #
        # vmbitrix source
        # https://repo.bitrix.info/sources/oracle/mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm
        # https://repo.bitrix.info/sources/oracle/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm
        PACKAGES_LINK="${REPO_SOURCE_URL}oracle/"
        PACKAGE_CONNECTOR_C="mariadb-connector-c-3.2.6-1.el9_0.x86_64.rpm"
        PACKAGE_PERL_DBD_MYSQL="perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
    fi
    if [[ ${OS} == 'CentOS Stream' ]];
    then
        # original source
        # https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/Packages/mariadb-connector-c-3.2.6-1.el9.x86_64.rpm
        # https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/Packages/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm
        # PACKAGES_LINK="https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/Packages/"
        #
        # vmbitrix source
        # https://repo.bitrix.info/sources/centos/mariadb-connector-c-3.2.6-1.el9.x86_64.rpm
        # https://repo.bitrix.info/sources/centos/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm
        PACKAGES_LINK="${REPO_SOURCE_URL}centos/"
        PACKAGE_CONNECTOR_C="mariadb-connector-c-3.2.6-1.el9.x86_64.rpm"
        PACKAGE_PERL_DBD_MYSQL="perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
    fi
    # original source
    #if [[ ${OS} == 'Rocky Linux' ]];
    #then
    #    LINK_CONNECTOR_C="${PACKAGES_LINK}m/${PACKAGE_CONNECTOR_C}"
    #    LINK_PERL_DBD_MYSQL="${PACKAGES_LINK}p/${PACKAGE_PERL_DBD_MYSQL}"
    #fi
    #if [[ ( ${OS} == 'AlmaLinux' ) || ( ${OS} == 'Oracle Linux' ) || ( ${OS} == 'CentOS Stream' ) ]];
    #then
    #    LINK_CONNECTOR_C="${PACKAGES_LINK}${PACKAGE_CONNECTOR_C}"
    #    LINK_PERL_DBD_MYSQL="${PACKAGES_LINK}${PACKAGE_PERL_DBD_MYSQL}"
    #fi
    #
    # vmbitrix source
    LINK_CONNECTOR_C="${PACKAGES_LINK}${PACKAGE_CONNECTOR_C}"
    LINK_PERL_DBD_MYSQL="${PACKAGES_LINK}${PACKAGE_PERL_DBD_MYSQL}"
    cd /tmp >> ${LOGS_FILE} 2>&1
    wget ${LINK_CONNECTOR_C} >> ${LOGS_FILE} 2>&1 || print_e "error: ${LINK_CONNECTOR_C}"
    wget ${LINK_PERL_DBD_MYSQL} >> ${LOGS_FILE} 2>&1 || print_e "error: ${LINK_PERL_DBD_MYSQL}"
    rpm -Uvh ${PACKAGE_CONNECTOR_C} ${PACKAGE_PERL_DBD_MYSQL} >> ${LOGS_FILE} 2>&1  || print_e "rpm error"
    rm -f /tmp/${PACKAGE_CONNECTOR_C} >> ${LOGS_FILE} 2>&1
    rm -f /tmp/${PACKAGE_PERL_DBD_MYSQL} >> ${LOGS_FILE} 2>&1
#
}

prepare_percona_install() {
#
    INSTALLED_PACKAGES=$(rpm -qa)
    if [[ $(echo "${INSTALLED_PACKAGES}" | grep -c "mariadb") -gt 0 ]];
    then
        MARIADB_PACKAGES=$(echo "${INSTALLED_PACKAGES}" | grep "mariadb")
        if [[ $(echo "${MARIADB_PACKAGES}" | grep -vc "mariadb-libs") -gt 0 ]];
        then
            print "$MBE0034"
        else
            dnf -y remove mariadb-libs > /dev/null 2>&1
            print "$MBE0035"
        fi
    fi
    
    if [[ $(echo "${INSTALLED_PACKAGES}" | grep -c "mysql") -gt 0 ]];
    then
        MYSQL_PACKAGES=$(echo "${INSTALLED_PACKAGES}" | grep "mysql-libs")
        if [[ $(echo "${MYSQL_PACKAGES}" | grep -vc "mysql-libs") -gt 0 ]];
        then
            print "$MBE0036"
        else
            dnf -y remove mysql-libs > /dev/null 2>&1
            print "$MBE0037"
        fi
    fi
#
}

configure_exclude() {
#
    YUM_CONF=/etc/yum.conf

    if [[ $(grep -c "exclude" ${YUM_CONF}) -gt 0 ]];
    then
        sed -i 's/^exclude=.\+/exclude=ansible1.9,mysql,mysql-server,mariadb,mariadb-*,Percona-XtraDB-*,Percona-*-55,Percona-*-56,Percona-*-51,Percona-*-50,Percona-Server-server-57-*/' ${YUM_CONF}
    else
        echo 'exclude=ansible1.9,mysql,mysql-server,mariadb,mariadb-*,Percona-XtraDB-*,Percona-*-55,Percona-*-56,Percona-*-51,Percona-*-50,Percona-Server-server-57-*' >> ${YUM_CONF}
    fi

    if [[ $(grep -v '^$\|^#' ${YUM_CONF} | grep -c "installonly_limit") -eq 0 ]];
    then
        echo "installonly_limit=2" >> ${YUM_CONF}
    else
        if [[ $(grep -v '^$\|^#' ${YUM_CONF} | grep -c "installonly_limit=5") -gt 0 ]];
        then
            sed -i "s/installonly_limit=5/installonly_limit=2/" ${YUM_CONF}
        fi
    fi

    DNF_CONF=/etc/dnf/dnf.conf

    if [[ $(grep -c "exclude" ${DNF_CONF}) -gt 0 ]];
    then
        sed -i 's/^exclude=.\+/exclude=ansible1.9,mysql,mysql-server,mariadb,mariadb-*,Percona-XtraDB-*,Percona-*-55,Percona-*-56,Percona-*-51,Percona-*-50,Percona-Server-server-57-*,perl-DBD-MySQL/' ${DNF_CONF}
    else
        echo 'exclude=ansible1.9,mysql,mysql-server,mariadb,mariadb-*,Percona-XtraDB-*,Percona-*-55,Percona-*-56,Percona-*-51,Percona-*-50,Percona-Server-server-57-*,perl-DBD-MySQL' >> ${DNF_CONF}
    fi

    if [[ $(grep -v '^$\|^#' ${DNF_CONF} | grep -c "installonly_limit") -eq 0 ]];
    then
        echo "installonly_limit=2" >> ${DNF_CONF}
    else
        if [[ $(grep -v '^$\|^#' ${DNF_CONF} | grep -c "installonly_limit=5") -gt 0 ]];
        then
            sed -i "s/installonly_limit=5/installonly_limit=2/" ${DNF_CONF}
        fi
    fi
#
}

test_bitrix_repo() {
#
#    if [[ $TEST_REPOSITORY -eq 1  ]];
#    then
#        REPO=yum-beta
#        REPONAME=bitrix-beta
#    elif [[ $TEST_REPOSITORY -eq 2 ]];
#    then
#        REPO=yum-testing
#        REPONAME=bitrix-testing
#    else
#        REPO=yum
#        REPONAME=bitrix
#    fi
#

    if [[ ${TEST_REPOSITORY} -eq 1 ]];
    then
        REPO=dnf-testing
        REPONAME=bitrix-testing-9
        REPOTEXT='Bitrix Testing Packages'
    else
        REPO=dnf
        REPONAME=bitrix-9
        REPOTEXT='Bitrix Packages'
    fi

    IS_BITRIX_REPO=$(dnf repolist enabled | grep ^bitrix -c)
    if [[ ${IS_BITRIX_REPO} -gt 0 ]];
    then
        print "$MBE0038" 1
        REPO_INSTALLED=$(grep -v '^$\|^#' ${REPOFILE9} | awk -F'=' '/baseurl=/{print $2}' | awk -F'/' '{print $4}')
        if [[ ${REPO_INSTALLED} != "${REPO}" ]];
        then
            print "$MBE0038" 1
            return 1
        fi
    fi
    return 0
#
}

configure_bitrix_repo() {
#
    test_bitrix_repo || return 1

    if [[ ${DEV_MODE} -eq 1 ]];
    then
        REPO_URL="http://10.0.1.39/bitrix/"
        GPGK="${REPO_URL}RPM-GPG-KEY-BitrixEnv-9"
    else
        REPO_URL="https://repo.bitrix.info/"
        GPGK="${REPO_URL}${REPO}/RPM-GPG-KEY-BitrixEnv-9"
        #GPGK="https://repo.bitrix.info/yum/RPM-GPG-KEY-BitrixEnv"
    fi

    # ToDo resign packages with valid SHA256 or more high chipers
    # 	https://www.redhat.com/en/blog/rhel-security-sha-1-package-signatures-distrusted-rhel-9
    # Red Hat Enterprise Linux 9 (RHEL 9) deprecated SHA-1 for signing for security reasons, it is still used by many for signing packages
    # enable SHA1 temprorary
    #update-crypto-policies --set LEGACY >> ${LOGS_FILE} 2>&1
    #update-crypto-policies --set DEFAULT:SHA1
    #update-crypto-policies --set DEFAULT
    print "$MBE0039" 1

    rpm --import "${GPGK}" >> ${LOGS_FILE} 2>&1 || print_e "$MBE0040 ${GPGK}"

    #REPOF=/etc/yum.repos.d/bitrix.repo
    #echo "[$REPONAME]" > $REPOF
    #echo "name=\$OS \$releasever - \$basearch" >> $REPOF
    #echo "failovermethod=priority" >> $REPOF
    #echo "baseurl=https://repo.bitrix.info/$REPO/el/$VER/\$basearch" >> $REPOF
    #echo "enabled=1" >> $REPOF
    #echo "gpgcheck=1" >> $REPOF
    #echo "gpgkey=$GPGK" >> $REPOF

    echo "[${REPONAME}]" >> ${REPOFILE9}
    echo "name=${REPOTEXT} for Enterprise Linux 9 - x86_64" >> ${REPOFILE9}
    if [[ ${DEV_MODE} -eq 1 ]];
    then
        echo "baseurl=${REPO_URL}\$releasever/\$basearch/" >> ${REPOFILE9}
    else
        echo "baseurl=${REPO_URL}${REPO}/el/\$releasever/\$basearch/" >> ${REPOFILE9}
    fi
    echo "enabled=1" >> ${REPOFILE9}
    echo "gpgcheck=1" >> ${REPOFILE9}
    echo "priority=1" >> ${REPOFILE9}
    echo "failovermethod=priority" >> ${REPOFILE9}
    echo "gpgkey=${GPGK}" >> ${REPOFILE9}
    print "$MBE0041" 1
#
}

dnf_update() {
#
    print "$MBE0042" 1
    dnf -y update >> ${LOGS_FILE} 2>&1 || print_e "$MBE0043"
#
}

configure_dnf() {
#
    dnf -y install dnf-plugins-core yum-utils >> ${LOGS_FILE} 2>&1
#
}

ask_for_password() {
#
    MYSQL_ROOTPW=
    LIMIT=5
    until [[ -n "${MYSQL_ROOTPW}" ]]; do
        password_check=

        if [[ ${LIMIT} -eq 0 ]];
        then
            print "$MBE0044"
            return 1
        fi
        LIMIT=$(( ${LIMIT} - 1 ))

        read -s -r -p "$MBE0045" MYSQL_ROOTPW
        echo
        read -s -r -p "$MBE0046" password_check

        if [[ ( -n ${MYSQL_ROOTPW} ) && ( "${MYSQL_ROOTPW}" = "${password_check}" ) ]];
        then
            :
        else
            [[ "${MYSQL_ROOTPW}" != "${password_check}" ]] && print "$MBE0047"
            [[ -z "${MYSQL_ROOTPW}" ]] && print "$MBE0048"
            MYSQL_ROOTPW=
        fi
    done
#
}

update_mysql_rootpw() {
#
    esc_pass=$(basic_single_escape "${MYSQL_ROOTPW}")
#    if [[ $MYSQL_UNI_VERSION -ge 57 ]];
#    then
#        my_query "ALTER USER 'root'@'localhost' IDENTIFIED BY '$esc_pass';" "$mysql_update_config"
#        my_query_rtn=$?
#    else
#        my_query "UPDATE mysql.user SET Password=PASSWORD('$esc_pass') WHERE User='root'; FLUSH PRIVILEGES;" "$mysql_update_config"
#        my_query_rtn=$?
#    fi
    my_query "ALTER USER 'root'@'localhost' IDENTIFIED BY '$esc_pass';" "$mysql_update_config"
    my_query_rtn=$?

    if [[ ${my_query_rtn} -eq 0 ]];
    then
        log_to_file "$MBE0048"
        print "$MBE0049" 1
        rm -f ${mysql_update_config}
    else
        log_to_file "$MBE0050"
        rm -f ${mysql_update_config}
        return 1
    fi

    my_config
    log_to_file "$MBE0051 ${MYSQL_CNF}"
    print "$MBE0051 ${MYSQL_CNF}" 1
#
}

configure_mysql_passwords() {
#
    [[ -z ${MYSQL_VERSION} ]] && get_mysql_package

    my_start

    log_to_file "$MBE0052 $MYSQL_VERSION($MYSQL_UNI_VERSION)"

    ASK_USER_FOR_PASSWORD=0
    if [[ ! -f ${MYSQL_CNF} ]];
    then
        log_to_file "$MBE0053 $MYSQL_CNF"
#        if [[ $MYSQL_UNI_VERSION -ge 57  ]];
#        then
#            MYSQL_LOG_FILE=/var/log/mysqld.log
#            MYSQL_ROOTPW=$(grep 'temporary password' $MYSQL_LOG_FILE | awk '{print $NF}')
#            MYSQL_ROOTPW_TYPE=temporary
#        else
#            MYSQL_ROOTPW=
#            MYSQL_ROOTPW_TYPE=empty
#        fi
        MYSQL_LOG_FILE=/var/log/mysqld.log
        MYSQL_ROOTPW=$(grep 'temporary password' ${MYSQL_LOG_FILE} | awk '{print $NF}')
        MYSQL_ROOTPW_TYPE=temporary

        local my_temp=${MYSQL_CNF}.temp
        my_config "$my_temp"
        my_query "status;" "$my_temp"
        my_query_rtn=$?
        if [[ ${my_query_rtn} -gt 0 ]];
        then
            if [[ ${MYSQL_ROOTPW_TYPE} == "temporary" ]];
            then
                log_to_file "$MBE0055"
            else
                log_to_file "$MBE0054"
            fi
            ASK_USER_FOR_PASSWORD=1
            mysql_update_config=
        else
            ASK_USER_FOR_PASSWORD=2
            mysql_update_config=${my_temp}
        fi
    else
        MYSQL_ROOTPW_TYPE=saved
        log_to_file "$MBE0056 $MYSQL_CNF"
        my_query "status;"
        my_query_rtn=$?
        if [[ ${my_query_rtn} -gt 0 ]];
        then
            log_to_file "$MBE0063"
            ASK_USER_FOR_PASSWORD=1
            mysql_update_config=
        else
            test_empty_password=$(cat ${MYSQL_CNF} | grep password | awk -F'=' '{print $2}' | sed -e "s/^\s\+//;s/\s\+$//" )
            if [[ ( -z ${test_empty_password} ) || ( ${test_empty_password} == '""' ) || ( ${test_empty_password} == "''" ) ]];
            then
                ASK_USER_FOR_PASSWORD=2
                cp -f ${MYSQL_CNF} ${MYSQL_CNF}.temp
                mysql_update_config=${MYSQL_CNF}.temp
            fi
        fi
    fi

    if [[ ${ASK_USER_FOR_PASSWORD} -eq 1 ]];
    then
        if [[ ${MYSQL_ROOTPW_TYPE} == "temporary" ]];
        then
            log_to_file "$MBE0055"
            [[ ${SILENT} -eq 0 ]] && print "$MBE0055" 2
        else
            log_to_file "$MBE0054"
            [[ ${SILENT} -eq 0 ]] && print "$MBE0054" 2
        fi

        if [[ ${SILENT} -eq 0 ]];
        then
            read -r -p "$MBE0057" user_answer
            [[ $( echo "${user_answer}" | grep -wci "\(No\|n\)"  ) -gt 0  ]] && return 1
            ask_for_password
            [[ $? -gt 0 ]] && return 2
        else
            if [[ -n "${MYPASSWORD}" ]];
            then
                MYSQL_ROOTPW="${MYPASSWORD}"
            else
                log_to_file "$MBE0058"
                return 1
            fi
        fi
        my_config
        print "$MBE0059" 1
    elif [[ ${ASK_USER_FOR_PASSWORD} -eq 2 ]];
    then
        log_to_file "$MBE0063"
        if [[ ${SILENT} -eq 0 ]];
        then
            read -r -p "$MBE0064" user_answer
            [[ $( echo "${user_answer}" | grep -wci "\(No\|n\)" ) -gt 0 ]] && return 1
            ask_for_password 
            [[ $? -gt 0 ]] && return 2
        else
            if [[ -n "${MYPASSWORD}" ]];
            then
                MYSQL_ROOTPW="${MYPASSWORD}"
            else
                MYSQL_ROOTPW="$(randpw)"
            fi
        fi
        update_mysql_rootpw
    else
        log_to_file "$MBE0065"
        if [[ -n "${MYPASSWORD}" ]];
        then
            MYSQL_ROOTPW="${MYPASSWORD}"
            update_mysql_rootpw
        else
            if [[  ( ${SILENT} -eq 0 ) && ( ${MYSQL_UNI_VERSION} -ge 57 ) ]];
            then
                print "$MBE0066" 1
                print "$MBE0067" 2
            fi
        fi
    fi
    my_additional_security
    log_to_file "$MBE0068"
    print "$MBE0068" 1
#
}

configure_postgresql_password() {
    local password=""
    local escaped_password=""

    if [[ -z "${PGSQL_PASSWORD// }" ]];
    then
        password=$(randpw)
        escaped_password=$(basic_single_escape "${password}")
    else
        password="${PGSQL_PASSWORD}"
        escaped_password=$(basic_single_escape "${password}")
    fi

    service_postgresql start
    
    create_pgpass_file "${escaped_password}"
    if [[ $? -ne 0 ]];
    then
        log_to_file "$MBEPG06"
        return 1
    fi

    pgsql_query "ALTER USER postgres WITH PASSWORD '${escaped_password}';" "postgres"
    if [[ $? -ne 0 ]];
    then
        log_to_file "$MBEPG07"
        return 1
    fi

    update_pgsql_config
    if [[ $? -ne 0 ]];
    then
        log_to_file "$MBEPG08"
        return 1
    fi

    pgsql_query "SELECT 1 as test;"
    if [[ $? -ne 0 ]];
    then
        log_to_file "$MBEPG09"
        return 1
    fi

    print "$MBEPG11" 1
    print "$MBEPG12" 2
    print "$MBEPG10" 1
    log_to_file "$MBEPG10"
    return 0
}

os_version() {
#
#    IS_CENTOS7=$(grep -c 'CentOS Linux release' $RELEASE_FILE)
#    IS_CENTOS73=$(grep -c "CentOS Linux release 7.3" $RELEASE_FILE)
#    IS_X86_64=$(uname -p | grep -wc 'x86_64')
#    if [[ $IS_CENTOS7 -gt 0 ]];
#    then
#        VER=$(awk '{print $4}' $RELEASE_FILE | awk -F'.' '{print $1}')
#    else
#        VER=$(awk '{print $3}' $RELEASE_FILE | awk -F'.' '{print $1}')
#    fi

#    VER=$(awk '{print $4}' ${RELEASE_FILE} | awk -F'.' '{print $1}')

    [[ ( ${VERSION} -eq 9 ) ]] || print_e "$MBE0075 ${VERSION}."
#
}

prepare_ansible_config() {
#
    rm -f /etc/ansible/ansible.cfg
    mv /etc/ansible/ansible.cfg.vmbitrix9 /etc/ansible/ansible.cfg
#
}

install_community_general_ansible_collection() {
#
    COMMUNITY_GENERAL_ANSIBLE_GALAXY_COLLECTION_URL=https://github.com/ansible-collections/community.general/archive/refs/tags/
    COMMUNITY_GENERAL_ANSIBLE_GALAXY_COLLECTION_VERSION=8.5.0
    mkdir -p /root/.ansible/collections/ >> ${LOGS_FILE} 2>&1
    cd /root >> ${LOGS_FILE} 2>&1
    wget ${COMMUNITY_GENERAL_ANSIBLE_GALAXY_COLLECTION_URL}${COMMUNITY_GENERAL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    tar xvf ${COMMUNITY_GENERAL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz > /dev/null 2>&1
    ansible-galaxy collection install community.general-${COMMUNITY_GENERAL_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
    rm -f ${COMMUNITY_GENERAL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    rm -rf community.general-${COMMUNITY_GENERAL_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
#
}

install_community_mysql_ansible_collection() {
#
    COMMUNITY_MYSQL_ANSIBLE_GALAXY_COLLECTION_URL=https://github.com/ansible-collections/community.mysql/archive/refs/tags/
    COMMUNITY_MYSQL_ANSIBLE_GALAXY_COLLECTION_VERSION=3.9.0
    mkdir -p /root/.ansible/collections/ >> ${LOGS_FILE} 2>&1
    cd /root >> ${LOGS_FILE} 2>&1
    wget ${COMMUNITY_MYSQL_ANSIBLE_GALAXY_COLLECTION_URL}${COMMUNITY_MYSQL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    tar xvf ${COMMUNITY_MYSQL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz > /dev/null 2>&1
    ansible-galaxy collection install community.mysql-${COMMUNITY_MYSQL_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
    rm -f ${COMMUNITY_MYSQL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    rm -rf community.mysql-${COMMUNITY_MYSQL_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
#
}

install_community_pgsql_ansible_collection() {
#
    COMMUNITY_PGSQL_ANSIBLE_GALAXY_COLLECTION_URL=https://github.com/ansible-collections/community.postgresql/archive/refs/tags/
    COMMUNITY_PGSQL_ANSIBLE_GALAXY_COLLECTION_VERSION=3.1.0
    mkdir -p /root/.ansible/collections/ >> ${LOGS_FILE} 2>&1
    cd /root >> ${LOGS_FILE} 2>&1
    wget ${COMMUNITY_PGSQL_ANSIBLE_GALAXY_COLLECTION_URL}${COMMUNITY_PGSQL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    tar xvf ${COMMUNITY_PGSQL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz > /dev/null 2>&1
    ansible-galaxy collection install community.postgresql-${COMMUNITY_PGSQL_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
    rm -f ${COMMUNITY_PGSQL_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    rm -rf community.postgresql-${COMMUNITY_PGSQL_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
#
}

install_community_rabbitmq_ansible_collection() {
#
    COMMUNITY_RABBITMQ_ANSIBLE_GALAXY_COLLECTION_URL=https://github.com/ansible-collections/community.rabbitmq/archive/refs/tags/
    COMMUNITY_RABBITMQ_ANSIBLE_GALAXY_COLLECTION_VERSION=1.3.0
    mkdir -p /root/.ansible/collections/ >> ${LOGS_FILE} 2>&1
    cd /root >> ${LOGS_FILE} 2>&1
    wget ${COMMUNITY_RABBITMQ_ANSIBLE_GALAXY_COLLECTION_URL}${COMMUNITY_RABBITMQ_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    tar xvf ${COMMUNITY_RABBITMQ_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz > /dev/null 2>&1
    ansible-galaxy collection install community.rabbitmq-${COMMUNITY_RABBITMQ_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
    rm -f ${COMMUNITY_RABBITMQ_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    rm -rf community.rabbitmq-${COMMUNITY_RABBITMQ_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
#
}

install_posix_ansible_collection() {
#
    POSIX_ANSIBLE_GALAXY_COLLECTION_URL=https://github.com/ansible-collections/ansible.posix/archive/refs/tags/
    POSIX_ANSIBLE_GALAXY_COLLECTION_VERSION=1.6.1
    mkdir -p /root/.ansible/collections/ >> ${LOGS_FILE} 2>&1
    cd /root >> ${LOGS_FILE} 2>&1
    wget ${POSIX_ANSIBLE_GALAXY_COLLECTION_URL}${POSIX_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    tar xvf ${POSIX_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz > /dev/null 2>&1
    ansible-galaxy collection install ansible.posix-${POSIX_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
    rm -f ${POSIX_ANSIBLE_GALAXY_COLLECTION_VERSION}.tar.gz >> ${LOGS_FILE} 2>&1
    rm -rf ansible.posix-${POSIX_ANSIBLE_GALAXY_COLLECTION_VERSION} >> ${LOGS_FILE} 2>&1
#
}

disable_dnf_makecache() {
#
    systemctl stop dnf-makecache.timer >> ${LOGS_FILE} 2>&1
    systemctl disable dnf-makecache.timer >> ${LOGS_FILE} 2>&1
#
}

enable_dnf_makecache() {
#
    systemctl enable dnf-makecache.timer >> ${LOGS_FILE} 2>&1
    systemctl start dnf-makecache.timer >> ${LOGS_FILE} 2>&1
#
}

awaiting_task_run() {
#
    task_name="${1}"
    wait_count=0
    while [[ "$(ps -ef | grep ansible-playbook | grep -v grep | wc -l)" -gt 0 ]]
    do
        (( wait_count++ ))
    done
    if [[ $task_name -eq 1 ]];
    then
        echo "$MBE0110$wait_count" >> ${LOGS_FILE} 2>&1
    fi
    if [[ $task_name -eq 2 ]];
    then
        echo "$MBE0111$wait_count" >> ${LOGS_FILE} 2>&1
    fi
#
}

check_pool_and_push_options() {
#
    if [[ ( ${PUSH} -gt 0 ) && ( ${POOL} -eq 0 ) ]];
    then
        print_e "$MBE0263"
    fi
#
}

show_os_and_version() {
#
    echo -en "$MBE0093 \e[1;32m${OS} ${VERSION}\e[0m" && echo -e ""
#
}
