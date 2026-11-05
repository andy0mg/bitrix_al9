# Ansible: 1С-Битрикс «Управление сайтом» на Debian 13

Плейбук повторяет главу курса «Настройка окружения Debian 13»
(https://dev.1c-bitrix.ru/learning/course/?COURSE_ID=32&CHAPTER_ID=032912):
Apache 2.4 + PHP (по умолчанию 8.4, можно 8.1–8.5; mod_php, порт 8090) за Nginx, MariaDB, Redis,
конфиги из официального архива `debian.zip`, загрузка `bitrixsetup.php`.
Push-сервер не ставится: для «Управления сайтом» он не нужен (по мануалу).

## Быстрый старт: скрипт [`install.sh`](install.sh)

Скрипт ставит Ansible с нужными коллекциями, скачивает этот каталог в `/opt/bitrix-ansible`
и создаёт `inventory.ini` для запуска на том же сервере. С `--run` сразу запускает плейбук:

```bash
curl -fsSL https://raw.githubusercontent.com/andy0mg/bitrix_al9/main/debian13/install.sh | bash -s -- --run
```

После скачивания скрипт спрашивает, что ставить: обновление ОС и перезагрузку, Redis,
exim4, фаервол nftables, cron агентов, версию PHP, `bitrixsetup.php`/`restore.php`, `BITRIX_VA_VER`,
имя БД и пользователя. Ответы сохраняются в `/opt/bitrix-ansible/local.yml`, передаются
плейбуку через `-e @local.yml` и при следующем запуске предлагаются по умолчанию.
`--yes` пропускает вопросы, `--configure` задаёт их заново. Без терминала (например, в CI)
вопросы не задаются.

Без `--run` только скачивает: поправьте ответы или `group_vars/all.yml` и запустите плейбук сами.
Параметры: `--dir`, `--branch`, а всё после `--` уходит в `ansible-playbook`
(например `-- -e bitrix_configure_firewall=true`). Повторный запуск обновляет плейбук,
но сохраняет `inventory.ini`, `group_vars/all.yml`, `local.yml` и `credentials/`.

## Запуск вручную (с управляющей машины)

```bash
ansible-galaxy collection install -r requirements.yml
cp inventory.ini.example inventory.ini   # впишите IP сервера
# пароль БД можно не задавать: он сгенерируется в credentials/<host>-db_password
ansible-playbook -i inventory.ini site.yml
```

После прогона откройте `http://<сервер>/bitrixsetup.php` и пройдите мастер установки.
На шаге БД укажите: сервер `localhost`, БД/пользователь/пароль из `group_vars/all.yml`.

## Основные переменные (`group_vars/all.yml`)

| Переменная | По умолчанию | Что делает |
|---|---|---|
| `bitrix_db_name` / `bitrix_db_user` / `bitrix_db_password` | `portal` / `bitrix` / генерируется | БД и пользователь MariaDB |
| `bitrix_site_root` | `/var/www/html/bx-site` | Корень сайта (так в конфигах архива) |
| `bitrix_install_redis` | `true` | Redis с конфигом из архива |
| `bitrix_upgrade_system` / `bitrix_reboot_after_upgrade` | `true` / `false` | `apt upgrade` и перезагрузка |
| `bitrix_configure_firewall` | `false` | nftables: 22, 80, 443 (+ `bitrix_extra_ports`) |
| `bitrix_php_settings` | см. файл | timezone, memory_limit, max_input_vars и т.п. |
| `bitrix_enable_cron` | `true` | `cron_events.php` раз в 5 минут от www-data |
| `bitrix_install_mta` | `false` | exim4 (internet site) для отправки почты |
| `bitrix_mysql_settings` | см. файл | доп. параметры MariaDB |
| `bitrix_php_version` | `8.4` | версия PHP: 8.4 из Debian, 8.1/8.2/8.3/8.5 из packages.sury.org |
| `bitrix_va_ver` | `9.0.7` | `SetEnv BITRIX_VA_VER` в Apache, чтобы проверки Битрикса не ругались |
| `bitrix_apache_listen` | `127.0.0.1:8090` | адрес Apache за nginx |
| `bitrix_download_setup_script` | `true` | Скачать `bitrixsetup.php` в корень сайта |

Повторный запуск безопасен: архив скачивается один раз, файлы сайта не трогаются,
если в корне уже есть `bitrix/`.

Из [bitrix-gt](https://github.com/YogSottot/bitrix-gt) взяты: генерация пароля БД,
доп. настройки PHP и MariaDB (`innodb_strict_mode=OFF`, `max_allowed_packet`, buffer pool),
cron для агентов, nftables, exim4 в режиме internet site, `vm.overcommit_memory=1` для Redis,
`PrivateTmp=false` для Apache, Apache только на 127.0.0.1, php-curl и catdoc,
`restore.php` и финальная проверка, что `bitrixsetup.php` отдаётся через nginx.

`credentials/` содержит пароли, не коммитьте его (есть в `.gitignore`).
