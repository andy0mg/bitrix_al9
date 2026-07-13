# Установка full-node (одна VM) — команды `dnf`

Пошаговая ручная установка всех компонентов Bitrix Environment 9 на одной виртуальной машине.
Команды соответствуют логике скрипта [`install-full-node.sh`](install-full-node.sh).

**ОС:** Rocky Linux 9 / AlmaLinux 9 / Oracle Linux 9 / CentOS Stream 9 (x86_64)  
**Права:** root  
**SELinux:** должен быть отключён (`setenforce 0` + `SELINUX=disabled` в `/etc/selinux/config`, затем reboot)

> Автоматическая установка (рекомендуется):  
> `./cluster/run.sh full-node -s -c cluster/cluster.env -H server1 -M 'YourRootPassword' --with-transformer`

---

## 0. Переменные (задайте перед установкой)

```bash
# Имя хоста и пароли — замените на свои
export HOSTNAME_FQDN=server1.example.com
export MYSQL_ROOT_PASSWORD='ChangeMeRoot'
export PGSQL_PASSWORD='ChangeMePg'
export OPENSEARCH_HEAP_SIZE=2g

# Версии (по умолчанию как в bitrix-env-9)
export MYSQL_VERSION=8.0          # или 8.4
export PGSQL_VERSION=16           # или 15; по умолчанию в скрипте — 13 из AppStream
export NODEJS_VERSION=22
export REDIS_VERSION=8.2
export PHP_VERSION=8.2

hostnamectl set-hostname "${HOSTNAME_FQDN}"
```

---

## 1. Подготовка системы и репозитории

```bash
# Обновление системы
dnf -y update

# Плагины dnf (config-manager, yum-utils)
dnf -y install dnf-plugins-core yum-utils

# EPEL — зависимости для сторонних пакетов
rpm --import https://cdimage.debian.org/mirror/fedora/epel/RPM-GPG-KEY-EPEL-9
dnf -y install https://cdimage.debian.org/mirror/fedora/epel/epel-release-latest-9.noarch.rpm

# REMI — PHP 8.2 и Redis из remi-модулей
rpm --import http://rpms.famillecollet.com/RPM-GPG-KEY-remi
dnf -y install http://rpms.famillecollet.com/enterprise/remi-release-9.rpm

# CodeReady Builder (Rocky/Alma/CentOS Stream) — build-зависимости
dnf config-manager --set-enabled crb
# Oracle Linux 9 вместо crb:
# dnf -y install dnf-plugins-core
# dnf config-manager --enable ol9_codeready_builder

# Исключить конфликтующие mysql/mariadb из стандартных репозиториев
grep -q '^exclude=' /etc/yum.conf || echo 'exclude=ansible1.9,mysql,mysql-server,mariadb,mariadb-*,Percona-XtraDB-*,Percona-*-55,Percona-*-56,Percona-*-51,Percona-*-50,Percona-Server-server-57-*' >> /etc/yum.conf

# Утилиты и логирование
dnf -y install logrotate rsyslog rsyslog-gnutls rsyslog-gssapi rsyslog-logrotate rsyslog-relp
dnf -y install etckeeper psmisc mc htop bzip2 tar zip unzip unrar rsync curl wget vi vim nmap initscripts

dnf clean all
```

---

## 2. Репозиторий Bitrix и Percona

```bash
# Репозиторий Bitrix Environment 9
rpm --import https://repo.bitrix.info/dnf/RPM-GPG-KEY-BitrixEnv-9
cat >> /etc/yum.repos.d/bitrix-9.repo <<'EOF'
[bitrix-9]
name=Bitrix Packages for Enterprise Linux 9 - x86_64
baseurl=https://repo.bitrix.info/dnf/el/$releasever/$basearch/
enabled=1
gpgcheck=1
priority=1
failovermethod=priority
gpgkey=https://repo.bitrix.info/dnf/RPM-GPG-KEY-BitrixEnv-9
EOF

# Percona Server 8.0 или 8.4
dnf -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
if [[ "${MYSQL_VERSION}" == "8.4" ]]; then
  percona-release enable ps-84-lts release
  percona-release setup -y ps84-lts
else
  percona-release enable ps-80 release
  percona-release setup -y ps80
fi

# Удалить mariadb-libs / mysql-libs, если мешают Percona (при отсутствии установленного сервера)
dnf -y remove mariadb-libs mysql-libs 2>/dev/null || true
```

---

## 3. PHP 8.2 (модуль REMI)

```bash
# Включить основной remi и выбрать PHP 8.2
sed -i -e '/\[remi\]/,/^\[/s/enabled=0/enabled=1/' /etc/yum.repos.d/remi.repo
dnf module disable php:remi-7.4 php:remi-8.0 php:remi-8.1 php:remi-8.3 php:remi-8.4 php:remi-8.5 -y
dnf module enable php:remi-8.2 -y
dnf module install php:remi-8.2 -y

# PHP и расширения для Bitrix
dnf -y install \
  php php-mysqli php-pgsql \
  php-pecl-apcu php-pecl-zendopcache php-pecl-redis6 \
  php-pecl-msgpack php-pecl-igbinary

# Убрать php-fpm (Bitrix использует httpd + mod_php)
systemctl disable --now php-fpm 2>/dev/null || true
dnf -y remove php-fpm
```

---

## 4. Веб-сервер и Python

```bash
# Apache (backend за bx-nginx)
dnf -y install httpd httpd-core httpd-devel httpd-filesystem httpd-tools

# Python 3.11 — утилиты управления Bitrix
dnf -y install \
  python3.11 python3.11-libs python3.11-pip-wheel python3.11-setuptools-wheel \
  python3.11-PyMySQL python3.11-psycopg2

# Дополнительные perl-модули и кодировки
dnf -y install perl-lib perl-Sys-Hostname perl-IO-Interface perl-DBI perl-DBD-Pg glibc-gconv-extra
```

---

## 5. Percona MySQL

```bash
dnf -y install \
  percona-server-server percona-server-client percona-server-shared \
  percona-server-devel percona-icu-data-files

systemctl enable --now mysqld

# Задать root-пароль (временный пароль — в /var/log/mysqld.log)
TEMP_PW=$(grep 'temporary password' /var/log/mysqld.log 2>/dev/null | tail -1 | awk '{print $NF}')
if [[ -n "${TEMP_PW}" ]]; then
  mysql --connect-expired-password -uroot -p"${TEMP_PW}" \
    -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
else
  mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null || true
fi

cat > /root/.my.cnf <<EOF
[client]
user=root
password="${MYSQL_ROOT_PASSWORD}"
EOF
chmod 600 /root/.my.cnf
```

---

## 6. PostgreSQL

```bash
# Для PG 15/16 — включить модуль; для 13 — пакеты из AppStream по умолчанию
if [[ "${PGSQL_VERSION}" == "15" || "${PGSQL_VERSION}" == "16" ]]; then
  dnf module enable postgresql:${PGSQL_VERSION} -y
fi

dnf -y install postgresql-server postgresql postgresql-contrib
postgresql-setup --initdb
systemctl enable --now postgresql

# Пароль пользователя postgres (опционально)
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '${PGSQL_PASSWORD}';"
```

---

## 7. Node.js 22, Redis и Push-сервер

```bash
# Node.js 22 из NodeSource (временно отключаем appstream)
dnf config-manager --set-disabled appstream   # Oracle: ol9_appstream
curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
dnf -y install nodejs npm
dnf config-manager --set-enabled appstream

# Redis 8.2 из REMI
dnf module enable redis:remi-8.2 -y
dnf -y install redis
systemctl enable --now redis

# Push server Bitrix
dnf -y install bx-push-server
```

---

## 8. Пакеты Bitrix Environment

```bash
# Основной мета-пакет: nginx-конфиги, httpd, ansible, push, утилиты /opt/webdir
dnf -y install bitrix-env

# Просмотр doc/xls в Bitrix
dnf -y install bx-catdoc

# Nginx из репозитория Bitrix (если не подтянулся с bitrix-env)
dnf -y install bx-nginx
```

---

## 9. Memcached

```bash
dnf module enable memcached:remi -y
dnf -y install memcached

# На full-node memcached слушает только localhost
sed -i 's/^OPTIONS=.*/OPTIONS="-l 127.0.0.1"/' /etc/sysconfig/memcached
systemctl enable --now memcached
```

---

## 10. Transformer (опционально, Enterprise)

Требуется редакция **1С-Битрикс24: Энтерпрайз** (модули `transformer` + `transformercontroller`).

```bash
dnf -y install erlang rabbitmq-server libreoffice-headless ffmpeg
systemctl enable --now rabbitmq-server

export RABBITMQ_USER=transformer
export RABBITMQ_PASSWORD='ChangeMeRabbit'
export RABBITMQ_VHOST=bitrix

rabbitmqctl add_vhost "${RABBITMQ_VHOST}"
rabbitmqctl add_user "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}"
rabbitmqctl set_permissions -p "${RABBITMQ_VHOST}" "${RABBITMQ_USER}" ".*" ".*" ".*"
rabbitmqctl set_user_tags "${RABBITMQ_USER}" administrator

cat > /etc/bitrix-transformer.env <<EOF
SITE_NAME=default
RABBITMQ_HOST=127.0.0.1
RABBITMQ_PORT=5672
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
RABBITMQ_VHOST=${RABBITMQ_VHOST}
EOF
chmod 600 /etc/bitrix-transformer.env
```

---

## 11. OpenSearch (поиск)

```bash
# RPM с официального сайта (или пакет opensearch из репозитория, если доступен)
dnf -y install https://artifacts.opensearch.org/releases/bundle/opensearch/2/opensearch-2.15.0-linux-x64.rpm

LOCAL_IP=$(hostname -I | awk '{print $1}')

# Дополнить конфиг single-node (security отключена — как в шаблоне кластера)
cat >> /etc/opensearch/opensearch.yml <<EOF
cluster.name: bitrix-search
node.name: $(hostname -s)
network.host: ${LOCAL_IP}
discovery.type: single-node
plugins.security.disabled: true
EOF

mkdir -p /etc/opensearch/jvm.options.d
cat > /etc/opensearch/jvm.options.d/heap.options <<EOF
-Xms${OPENSEARCH_HEAP_SIZE}
-Xmx${OPENSEARCH_HEAP_SIZE}
EOF

chown -R opensearch:opensearch /etc/opensearch /var/lib/opensearch
systemctl enable --now opensearch
```

---

## 12. Запуск сервисов и push runtime

```bash
# Утилиты Bitrix (пароли, firewall, crypto key)
. /opt/webdir/bin/bitrix_utils.sh

# Инициализация push (SECURITY_KEY → /etc/sysconfig/push-server-multi)
export WS_HOST=$(hostname -I | awk '{print $1}')
if [[ -x /etc/init.d/push-server-multi ]]; then
  /etc/init.d/push-server-multi reset
fi
systemctl enable --now push-server

# Перезапуск основных сервисов
systemctl enable httpd nginx memcached redis mysqld postgresql opensearch push-server
systemctl restart httpd nginx memcached redis mysqld postgresql opensearch push-server
```

---

## 13. Firewall

```bash
systemctl enable --now firewalld

# Веб, memcached (локально), MySQL, PostgreSQL, push, OpenSearch
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --permanent --add-port=8010-8015/tcp
firewall-cmd --permanent --add-port=9010-9011/tcp
firewall-cmd --permanent --add-port=8893/tcp
firewall-cmd --permanent --add-port=8894/tcp
firewall-cmd --permanent --add-port=9200/tcp

# Transformer / RabbitMQ (если установлен)
# firewall-cmd --permanent --add-port=5672/tcp

firewall-cmd --reload
```

---

## 14. После установки сайта Битрикс

| Компонент | Куда указать |
|-----------|----------------|
| MySQL | `.settings.php` → хост `localhost` или IP VM |
| Memcached | `127.0.0.1:11211` — кеш и сессии |
| Push&Pull | Тип: Bitrix Push server 2.0; `WS_HOST`; `SECURITY_KEY` из `/etc/sysconfig/push-server-multi` |
| OpenSearch | Настройки → Поиск: `https://<IP_VM>:9200` |
| Transformer | Параметры из `/etc/bitrix-transformer.env` |

---

## Быстрая установка одной командой (скрипт)

```bash
cp cluster/cluster.env.example cluster/cluster.env
vi cluster/cluster.env   # пароли и домен

./cluster/run.sh full-node -s -c cluster/cluster.env \
  -H server1 -M "${MYSQL_ROOT_PASSWORD}" --with-transformer
```

Скрипт выполняет те же шаги, плюс настройку Ansible collections и firewall через `bitrix_utils.sh`.
