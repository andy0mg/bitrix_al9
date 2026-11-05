#!/usr/bin/env bash
# Скачивает всё нужное для установки окружения 1С-Битрикс на Debian 13:
# Ansible, коллекции и сам плейбук из репозитория. С --run сразу запускает
# плейбук на этом же сервере (ansible_connection=local).
#
#   curl -fsSL https://raw.githubusercontent.com/andy0mg/bitrix_al9/main/debian13/install.sh | bash -s -- --run
#
set -euo pipefail

REPO="andy0mg/bitrix_al9"
BRANCH="main"
DEST="/opt/bitrix-ansible"
RUN=0
ASK=auto   # auto: спрашивать, если есть терминал; yes: всегда; no: никогда
EXTRA_ARGS=()

usage() {
  cat <<USAGE
Использование: install.sh [опции] [-- аргументы ansible-playbook]

  --dir DIR       куда положить плейбук (по умолчанию $DEST)
  --branch NAME   ветка репозитория (по умолчанию $BRANCH)
  --run           сразу запустить плейбук на этом сервере
  --configure     задать вопросы о компонентах (по умолчанию, если есть терминал)
  -y, --yes       ничего не спрашивать: взять local.yml или значения по умолчанию
  -h, --help      эта справка

Всё после -- передаётся в ansible-playbook, например:
  install.sh --run -- -e bitrix_configure_firewall=true
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)    DEST="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --run)    RUN=1; shift ;;
    --configure) ASK=yes; shift ;;
    -y|--yes) ASK=no; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    *) echo "Неизвестный параметр: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root (или через sudo)." >&2
  exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "13" ]]; then
  echo "Внимание: скрипт рассчитан на Debian 13, а здесь ${PRETTY_NAME:-неизвестная ОС}." >&2
fi

echo "==> Устанавливаю Ansible и утилиты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
# Пакет ansible в Debian уже содержит community.general, community.mysql и ansible.posix
apt-get install -y -q ansible curl ca-certificates tar

echo "==> Скачиваю плейбук ($REPO@$BRANCH) в $DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" \
  | tar -xz -C "$TMP" --strip-components=1 --wildcards '*/debian13/*'
mkdir -p "$DEST"
# Не затираем локальные настройки и сгенерированные пароли
cp -a "$TMP/debian13/." "$DEST/.new"
for keep in inventory.ini credentials group_vars/all.yml local.yml; do
  if [[ -e "$DEST/$keep" ]]; then
    rm -rf "$DEST/.new/$keep"
    mkdir -p "$(dirname "$DEST/.new/$keep")"
    cp -a "$DEST/$keep" "$DEST/.new/$keep"
  fi
done
find "$DEST" -mindepth 1 -maxdepth 1 ! -name .new -exec rm -rf {} +
cp -a "$DEST/.new/." "$DEST/"
rm -rf "$DEST/.new"
chmod 0755 "$DEST/install.sh"

echo "==> Проверяю коллекции Ansible"
cd "$DEST"
for c in community.general community.mysql ansible.posix; do
  if ! ansible-galaxy collection list "$c" 2>/dev/null | grep -q "^$c "; then
    echo "    ставлю недостающие коллекции из requirements.yml"
    ansible-galaxy collection install -r requirements.yml
    break
  fi
done

if [[ ! -e inventory.ini ]]; then
  cat > inventory.ini <<INV
[bitrix]
localhost ansible_connection=local
INV
  echo "==> Создан inventory.ini для запуска на этом сервере"
fi

# ---------- Выбор компонентов ----------
# Ответы сохраняются в local.yml и при следующем запуске предлагаются по умолчанию.
LOCAL="$DEST/local.yml"

# Текущее значение: из local.yml, иначе значение по умолчанию
cur() {
  if [[ -f "$LOCAL" ]] && grep -q "^$1:" "$LOCAL"; then
    sed -n "s/^$1: *//p" "$LOCAL" | tail -n1 | tr -d '"'
  else
    echo "$2"
  fi
}

ask_bool() {   # ask_bool переменная "вопрос" true|false
  local def ans hint
  def="$(cur "$1" "$3")"
  [[ "$def" == "true" ]] && hint="Y/n" || hint="y/N"
  read -r -p "  $2 [$hint]: " ans </dev/tty || ans=""
  case "${ans,,}" in
    y|yes|д|да) ans=true ;;
    n|no|н|нет) ans=false ;;
    *) ans="$def" ;;
  esac
  echo "$1: $ans" >> "$LOCAL.tmp"
}

ask_str() {    # ask_str переменная "вопрос" значение_по_умолчанию
  local def ans
  def="$(cur "$1" "$3")"
  read -r -p "  $2 [${def:-пусто}]: " ans </dev/tty || ans=""
  if [[ "$ans" == "-" ]]; then ans=""      # "-" очищает значение
  elif [[ -z "$ans" ]]; then ans="$def"; fi
  echo "$1: \"$ans\"" >> "$LOCAL.tmp"
}

ask_choice() { # ask_choice переменная "вопрос" по_умолчанию "вариант1 вариант2 ..."
  local def ans
  def="$(cur "$1" "$3")"
  while true; do
    read -r -p "  $2 {${4// /|}} [$def]: " ans </dev/tty || ans=""
    ans="${ans:-$def}"
    [[ " $4 " == *" $ans "* ]] && break
    echo "    допустимо: $4" >/dev/tty
  done
  echo "$1: \"$ans\"" >> "$LOCAL.tmp"
}

if [[ "$ASK" == "auto" ]]; then
  if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then ASK=yes; else ASK=no; fi
fi

if [[ "$ASK" == "yes" ]]; then
  echo
  echo "==> Выберите компоненты (Enter — оставить значение в скобках)"
  : > "$LOCAL.tmp"
  ask_choice bitrix_php_version        "Версия PHP (8.4 из Debian, остальные из sury)" "8.4" "8.1 8.2 8.3 8.4 8.5"
  ask_bool bitrix_upgrade_system        "Обновить систему (apt dist-upgrade)?"          true
  ask_bool bitrix_reboot_after_upgrade  "Перезагрузить сервер после обновления?"        false
  ask_bool bitrix_install_redis         "Установить Redis?"                             true
  ask_bool bitrix_install_mta           "Установить exim4 для отправки почты?"          false
  ask_bool bitrix_configure_firewall    "Настроить фаервол nftables (22, 80, 443)?"     false
  ask_bool bitrix_enable_cron           "Добавить cron для агентов Битрикс?"            true
  ask_bool bitrix_download_setup_script "Скачать bitrixsetup.php?"                      true
  ask_bool bitrix_download_restore_script "Скачать restore.php?"                        true
  ask_str  bitrix_va_ver                "BITRIX_VA_VER («-» — не задавать)"             "9.0.7"
  ask_str  bitrix_db_name               "Имя базы данных"                               "portal"
  ask_str  bitrix_db_user               "Пользователь базы данных"                      "bitrix"
  { echo "---"; echo "# Выбор компонентов из install.sh, $(date '+%F %T')"; cat "$LOCAL.tmp"; } > "$LOCAL"
  rm -f "$LOCAL.tmp"
  echo "    сохранено в $LOCAL"
fi

VARS_ARGS=()
[[ -f "$LOCAL" ]] && VARS_ARGS=(-e "@$LOCAL")

if [[ $RUN -eq 1 ]]; then
  echo "==> Запускаю плейбук"
  ansible-playbook -i inventory.ini site.yml "${VARS_ARGS[@]}" "${EXTRA_ARGS[@]}"
else
  cat <<DONE

Готово. Плейбук лежит в $DEST.
Запуск:
  cd $DEST && ansible-playbook -i inventory.ini site.yml${VARS_ARGS:+ -e @local.yml}
Поменять выбор: $DEST/install.sh --configure
DONE
fi
