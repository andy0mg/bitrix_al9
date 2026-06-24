# Bitrix Environment 9 — кластерная установка

Набор скриптов для развёртывания Bitrix Environment 9 на **Enterprise Linux 9** (Rocky Linux, AlmaLinux, Oracle Linux, CentOS Stream) в режиме распределённого кластера: отдельная VM под каждую роль.

Скрипты основаны на официальном [`bitrix-env-9.sh`](bitrix-env-9.sh), но **не используют** `menu.sh` и management pool — конфигурация выполняется напрямую через role-скрипты и файл `cluster.env`.

## Архитектура

```
                    ┌─────────────────┐
                    │  VIP (keepalived)│
                    └────────┬────────┘
              ┌──────────────┴──────────────┐
         ┌────▼────┐                   ┌────▼────┐
         │   lb1   │                   │   lb2   │
         │ nginx   │                   │ nginx   │
         └────┬────┘                   └────┬────┘
              └──────────────┬──────────────┘
                    ┌────────▼────────┐
              ┌─────┴─────┐     ┌─────┴─────┐
              │   app1    │     │   app2    │
              │ nginx     │     │ nginx     │
              │ httpd+php │     │ httpd+php │
              │ memcached │     │ memcached │
              │transformer│     │           │
              └─────┬─────┘     └─────┬─────┘
                    └────────┬────────┘
         ┌──────────┬────────┼────────┬──────────┐
    ┌────▼────┐ ┌───▼───┐ ┌──▼──┐ ┌───▼────┐
    │mysql-m  │ │mysql-s│ │push │ │opensearch│
    └─────────┘ └───────┘ └─────┘ └────────┘
```

| Роль | Скрипт | Компоненты |
|------|--------|------------|
| Балансировщик | `cluster/install-balancer.sh` | bx-nginx, keepalived, upstream на app-серверы |
| Сервер приложений | `cluster/install-app.sh` | bitrix-env, nginx, httpd, PHP 8.2, memcached, опционально transformer |
| Push-сервер | `cluster/install-push.sh` | Node.js 22, redis, bx-push-server |
| MySQL master | `cluster/install-mysql-master.sh` | Percona Server 8.0/8.4, GTID, replication user |
| MySQL slave | `cluster/install-mysql-slave.sh` | Percona Server, репликация с master |
| OpenSearch | `cluster/install-opensearch.sh` | OpenSearch 2.x, single-node |

## Требования

- ОС: Rocky Linux 9 / AlmaLinux 9 / Oracle Linux 9 / CentOS Stream 9 (x86_64)
- Запуск **от root**
- SELinux должен быть **disabled** (скрипт предложит отключить и перезагрузить)
- Сетевой доступ к `repo.bitrix.info`, EPEL, REMI, Percona
- Для transformer: редакция **1С-Битрикс24: Энтерпрайз** (модули `transformer` + `transformercontroller`)

## Структура репозитория

```
bitrix-env-9.sh              # Монолитная установка «всё в одном» (обратная совместимость)
lib/
  bitrix-common.sh           # Общие функции установки BitrixEnv
  cluster-common.sh          # Загрузка cluster.env, рендер шаблонов
  cluster/
    run.sh                   # Точка входа: git fetch + install по роли
    cluster.env.example        # Пример конфигурации кластера
  install-balancer.sh
  install-app.sh
  install-push.sh
  install-mysql-master.sh
  install-mysql-slave.sh
  install-opensearch.sh
  templates/                 # Шаблоны nginx, keepalived, MySQL, OpenSearch, transformer
```

## Подготовка

### Вариант A: установка из Git (рекомендуется)

На каждой VM **не нужно** копировать весь репозиторий. Достаточно `cluster.env` и одной команды — скрипт подтянет из git только файлы своей роли в кэш `/var/cache/bitrix-cluster`.

1. Опубликуйте репозиторий на GitHub/GitLab (или укажите свой `BITRIX_CLUSTER_REPO`).

2. Создайте конфиг на VM (один раз):

```bash
vi /etc/bitrix-cluster.env
# BITRIX_CLUSTER_REPO=https://github.com/andy0mg/bitrix_al9.git
# MYSQL_ROOT_PASSWORD=..., VIP=..., APP_SERVERS=...
```

3. Запуск с любой VM (пример — app-сервер):

```bash
curl -fsSL https://raw.githubusercontent.com/andy0mg/bitrix_al9/main/cluster/run.sh -o /tmp/bitrix-run.sh
chmod +x /tmp/bitrix-run.sh
env BITRIX_CLUSTER_REPO=https://github.com/andy0mg/bitrix_al9.git \
  /tmp/bitrix-run.sh app -s -c /etc/bitrix-cluster.env -H app1 --with-transformer
```

Или если репозиторий уже клонирован локально:

```bash
./cluster/run.sh -r https://github.com/andy0mg/bitrix_al9.git app -s -c /etc/bitrix-cluster.env -H app1
```

Параметры git:

| Переменная / флаг | Описание |
|-------------------|----------|
| `BITRIX_CLUSTER_REPO` / `-r` | URL git-репозитория |
| `BITRIX_CLUSTER_REF` / `-b` | Ветка или тег (по умолчанию `main`) |
| `BITRIX_CLUSTER_CACHE` | Каталог кэша (по умолчанию `/var/cache/bitrix-cluster`) |

При повторном запуске используется кэш; при `git clone` выполняется `git pull` для обновления.

**Что подтягивается для каждой роли** (остальное не скачивается):

| Роль | Файлы |
|------|--------|
| `balancer` | lib/*, install-balancer.sh, шаблоны nginx/keepalived |
| `app` | lib/*, install-app.sh, transformer.env.tpl |
| `push` | lib/*, install-push.sh |
| `mysql-master` | lib/*, install-mysql-master.sh, replication.cnf |
| `mysql-slave` | lib/*, install-mysql-slave.sh, replication.cnf |
| `opensearch` | lib/*, install-opensearch.sh, opensearch.yml.tpl |

### Вариант B: локальная копия репозитория

1. Скопируйте репозиторий на VM (или клонируйте через `git clone`).

2. Сделайте скрипты исполняемыми:

```bash
chmod +x bitrix-env-9.sh cluster/*.sh
```

3. Создайте конфигурацию:

```bash
cp cluster/cluster.env.example cluster/cluster.env
vi cluster/cluster.env
```

4. Запуск напрямую:

```bash
./cluster/install-app.sh -c cluster/cluster.env -s -H app1
```

## Установка кластера

Рекомендуемый порядок:

### 1. MySQL master

```bash
./cluster/run.sh -r "${BITRIX_CLUSTER_REPO}" mysql-master -s -c /etc/bitrix-cluster.env -M 'YourRootPassword'
```

На slave-ноде в `cluster.env` задайте `MYSQL_SERVER_ID=2`.

### 2. MySQL slave

```bash
./cluster/run.sh -r "${BITRIX_CLUSTER_REPO}" mysql-slave -s -c /etc/bitrix-cluster.env -M 'YourRootPassword'
```

### 3. OpenSearch

```bash
./cluster/run.sh -r "${BITRIX_CLUSTER_REPO}" opensearch -s -c /etc/bitrix-cluster.env
```

### 4. Push-сервер

```bash
./cluster/run.sh -r "${BITRIX_CLUSTER_REPO}" push -s -c /etc/bitrix-cluster.env -H push1
```

После установки скопируйте `SECURITY_KEY` из `/etc/sysconfig/push-server-multi` — он понадобится в модуле Push&Pull.

### 5. Серверы приложений

На **первой** app-ноде (с transformer):

```bash
./cluster/run.sh -r "${BITRIX_CLUSTER_REPO}" app -s -c /etc/bitrix-cluster.env -H app1 --with-transformer
./cluster/run.sh -r "${BITRIX_CLUSTER_REPO}" app -s -c /etc/bitrix-cluster.env -H app2
```

> Transformer можно установить только на **одной** ноде (ограничение Bitrix). Параметры RabbitMQ сохраняются в `/etc/bitrix-transformer.env`.

### 6. Балансировщики

На **lb1** (MASTER) — в `cluster.env` или через переменные окружения:

```bash
export KEEPALIVED_STATE=MASTER KEEPALIVED_PRIORITY=100
./cluster/run.sh -r "${BITRIX_CLUSTER_REPO}" balancer -s -c /etc/bitrix-cluster.env -H lb1
```

На **lb2** (BACKUP):

```bash
export KEEPALIVED_STATE=BACKUP KEEPALIVED_PRIORITY=90
./cluster/run.sh -r "${BITRIX_CLUSTER_REPO}" balancer -s -c /etc/bitrix-cluster.env -H lb2
```

## Общие опции скриптов

| Опция | Описание |
|-------|----------|
| `-s` | Тихий режим (без интерактивных вопросов) |
| `-c path` | Путь к файлу `cluster.env` |
| `-H hostname` | Установить hostname (`hostnamectl`) |
| `-r` | URL git-репозитория (`BITRIX_CLUSTER_REPO`) |
| `-b` | Ветка git (`BITRIX_CLUSTER_REF`, по умолчанию `main`) |
| `-h` | Справка |

Дополнительно для MySQL:

| Опция | Описание |
|-------|----------|
| `-M password` | Пароль root MySQL |
| `-m 8.0\|8.4` | Версия Percona Server |

Дополнительно для app-сервера:

| Опция | Описание |
|-------|----------|
| `--with-transformer` | Установить стек transformer + transformercontroller |

## Монолитная установка (одна VM)

Для установки всех компонентов на одну машину (как в оригинальном BitrixEnv):

```bash
./bitrix-env-9.sh
```

Тихий режим с pool (если нужен классический сценарий BitrixVA):

```bash
./bitrix-env-9.sh -s -p -H server1 -M 'password'
```

Полная очистка системы от BitrixEnv:

```bash
./bitrix-env-9.sh clean
```

## Post-install (после установки сайта Битрикс)

1. **База данных** — в `.settings.php` укажите `MYSQL_MASTER` как хост БД.

2. **Memcached** — добавьте серверы memcached app-нод в настройки кеша/сессий.

3. **Push&Pull** — в админке: Настройки → Push and Pull:
   - тип сервера: Bitrix Push server 2.0;
   - URL push-хоста;
   - `SECURITY_KEY` с push-VM.

4. **OpenSearch** — Настройки → Поиск (модуль ≥ 25.0):
   - `https://OPENSEARCH_HOST:9200`;
   - учётные данные (если включена security).

5. **Transformer** — после установки модулей `transformer` и `transformercontroller`:
   - параметры из `/etc/bitrix-transformer.env`;
   - Drive: «Просмотр документов через Битрикс24».

6. **Web-кластер** — настройте модуль «Веб-кластер» в админке, укажите memcached и slave MySQL.

## Шаблоны конфигурации

Файлы в `cluster/templates/` разворачиваются скриптами на целевых VM:

| Шаблон | Назначение |
|--------|------------|
| `nginx-upstream.conf.tpl` | Upstream app-серверов |
| `http_balancer.conf.tpl` | HTTP-балансировщик nginx |
| `keepalived.conf.tpl` | VRRP + VIP |
| `mysql-master.cnf.d/replication.cnf` | GTID, binlog на master |
| `mysql-slave.cnf.d/replication.cnf` | read_only на slave |
| `opensearch.yml.tpl` | single-node OpenSearch |
| `transformer/transformer.env.tpl` | Параметры RabbitMQ для transformer |

## Ограничения

- Отдельные балансировщики — **нестандартная** схема для модуля Web Cluster Bitrix; конфиги взяты из документации, официальная поддержка не гарантируется.
- Синхронизация файлов между app-нодами (lsyncd/rsync) **не входит** в скрипты — настройте отдельно для multi-app.
- OpenSearch подключается в админке продукта, не через bash-скрипт.
- Transformer требует Enterprise-редацию и ставится только на одну app-VM.

## Логи

Во время установки лог пишется во временный файл `/tmp/bitrix-env-XXXXX.log`. При ошибке путь к логу выводится в консоль.

## Ссылки

- [BitrixEnv 9 — установка](https://training.bitrix24.com/support/training/course/index.php?COURSE_ID=113&LESSON_ID=29911)
- [Web Cluster](https://training.bitrix24.com/support/training/course/?CHAPTER_ID=026726)
- [Push server](https://training.bitrix24.com/support/training/course/?COURSE_ID=178&LESSON_ID=21618)
- [Transformer service](https://training.bitrix24.com/support/training/course/?LESSON_ID=31547)
