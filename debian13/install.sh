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
EXTRA_ARGS=()

usage() {
  cat <<USAGE
Использование: install.sh [опции] [-- аргументы ansible-playbook]

  --dir DIR       куда положить плейбук (по умолчанию $DEST)
  --branch NAME   ветка репозитория (по умолчанию $BRANCH)
  --run           сразу запустить плейбук на этом сервере
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
for keep in inventory.ini credentials group_vars/all.yml; do
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

if [[ $RUN -eq 1 ]]; then
  echo "==> Запускаю плейбук"
  ansible-playbook -i inventory.ini site.yml "${EXTRA_ARGS[@]}"
else
  cat <<DONE

Готово. Плейбук лежит в $DEST.
Проверьте group_vars/all.yml и запустите:
  cd $DEST && ansible-playbook -i inventory.ini site.yml
DONE
fi
