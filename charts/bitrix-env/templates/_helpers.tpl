{{/*
Expand the name of the chart.
*/}}
{{- define "bitrix.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name based on environment.
*/}}
{{- define "bitrix.fullname" -}}
{{- if .Values.fullnameOverride -}}
    {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
    {{- $env := include "bitrix.environment" . -}}
    {{- printf "%s-%s" .Release.Name .Release.Namespace | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "bitrix.environment" -}}
{{- if eq (include "bitrix.isProd" .) "true" -}}prod
{{- else if eq (include "bitrix.isAdmin" .) "true" -}}admin
{{- else -}}app{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "bitrix.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "bitrix.labels" -}}
helm.sh/chart: {{ include "bitrix.chart" . }}
{{ include "bitrix.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/environment: {{ .Values.environment }}
app.kubernetes.io/component: bitrix
{{- end }}

{{/*
Selector labels
*/}}
{{- define "bitrix.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bitrix.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Check if admin environment
*/}}
{{- define "bitrix.isAdmin" -}}
{{- if eq .Values.environment "admin" -}}
true
{{- end -}}
{{- end }}

{{/*
Check if prod environment
*/}}
{{- define "bitrix.isProd" -}}
{{- if eq .Values.environment "prod" -}}
true
{{- end -}}
{{- end }}

{{/*
Check if git feature is enabled
*/}}
{{- define "bitrix.gitEnabled" -}}
{{- if .Values.features.git -}}
true
{{- end -}}
{{- end }}

{{/*
Check if cron feature is enabled
*/}}
{{- define "bitrix.cronEnabled" -}}
{{- if .Values.features.cron -}}
true
{{- end -}}
{{- end }}

{{/*
Check if push feature is enabled
*/}}
{{- define "bitrix.pushEnabled" -}}
{{- if .Values.features.push -}}
true
{{- end -}}
{{- end }}

{{/*
Check if sphinx feature is enabled
*/}}
{{- define "bitrix.sphinxEnabled" -}}
{{- if .Values.features.sphinx -}}
true
{{- end -}}
{{- end }}

{{/*
Check if cache feature is enabled
*/}}
{{- define "bitrix.cacheEnabled" -}}
{{- if .Values.features.cache -}}
true
{{- end -}}
{{- end }}

# {{/*
# Check if session feature is enabled
# */}}
# {{- define "bitrix.sessionEnabled" -}}
# {{- if .Values.features.session -}}
# true
# {{- end -}}
# {{- end }}

{{/*
Check if php-exporter feature is enabled
*/}}
{{- define "bitrix.phpExporterEnabled" -}}
{{- if .Values.features.phpExporter -}}
true
{{- end -}}
{{- end }}

{{/*
Check if nginx-exporter feature is enabled
*/}}
{{- define "bitrix.nginxExporterEnabled" -}}
{{- if .Values.features.nginxExporter -}}
true
{{- end -}}
{{- end }}

##  Defining the starting script
{{- define "bitrix.StartScript" -}}
#!/bin/sh
set -e

{{- if .Values.features.git }}
##  Git Access Configuration
echo "Setting up SSH..."
mkdir -p ~/.ssh
cp /tmp/id_ed25519 ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519

{{- $repoUrl := .Values.git.repoUrl }}
{{- $host := regexReplaceAll "^[^@]+@([^:]+):.*$" $repoUrl "${1}" }}

ssh-keyscan -H {{ $host  }} >> ~/.ssh/known_hosts

if [ ! -d .git ]; then
  echo "Initializing git repository..."
  git init --initial-branch={{ .Values.git.branch }}
  git remote add origin {{ .Values.git.repoUrl }}
  git config user.email {{ .Values.git.email }}
  git config user.name {{ .Values.git.name }}
else
  echo "Git repository already exists"
fi
{{- else }}
echo "Git feature is disabled, skipping git configuration..."
{{- end }}

{{- $bitrixScripts := .Values.bitrixScripts }}

{{- if and (not $bitrixScripts.bitrixsetup) (not $bitrixScripts.restore) }}
## If you don't need the scripts, delete them if they are present
[ -f "restore.php" ] && rm restore.php
[ -f "bitrixsetup.php" ] && rm bitrixsetup*
{{- end }}

{{- if and $bitrixScripts.bitrixsetup $bitrixScripts.restore }}
##  You can use either bitrixsetup.php or restore.php, or you can not use them at all
[ -f "restore.php" ] && rm restore.php
[ -f "bitrixsetup.php" ] && rm bitrixsetup*
{{- fail "bitrixsetup.php and restore.php cannot be specified at the same time" }}
{{- end }}


##  If the installation already exists, the installation scripts are not downloaded, 
##  even if they are specified
{{- if $bitrixScripts.bitrixsetup }}
[ -f "restore.php" ] && rm restore.php
[ -d "bitrix/admin" ] && [ -f "bitrixsetup.php" ] && rm bitrixsetup*
[ ! -d "bitrix/admin" ] && wget https://www.1c-bitrix.ru/download/scripts/bitrixsetup.php -O bitrixsetup.php
{{- end }}
{{- if $bitrixScripts.restore }}
[ -f "bitrixsetup.php" ] && rm bitrixsetup*
[ -d "bitrix/admin" ] && [ -f "restore.php" ] && rm restore.php
[ ! -d "bitrix/admin" ] && wget https://www.1c-bitrix.ru/download/files/scripts/restore.php -O restore.php
{{- end }}

## mkdir -p tmp

##  Script start.php is connected in the php.ini config. However, when installing a project from scratch
##  the wizard will return an error that this file is missing. Therefore, we create empty start.php in advance
if [ ! -f "/home/bitrix/www/bitrix/modules/security/tools/start.php" ]; then
  mkdir -p /home/bitrix/www/bitrix/modules/security/tools/
  touch /home/bitrix/www/bitrix/modules/security/tools/start.php
fi

## autoload.php dummy file
if [ ! -f "/home/bitrix/www/bitrix/vendor/autoload.php" ]; then
  mkdir -p /home/bitrix/www/bitrix/vendor/
  touch /home/bitrix/www/bitrix/vendor/autoload.php
fi  

## Adding the required configs
DBCONN_FILE="/home/bitrix/www/bitrix/php_interface/dbconn.php"
SETTINGS_FILE="/home/bitrix/www/bitrix/.settings.php"
SETTINGS_EXTRA_FILE="/home/bitrix/www/bitrix/.settings_extra.php"
AFTER_CONNECT_D7_FILE="/home/bitrix/www/bitrix/php_interface/after_connect_d7.php"
CRON_EVENTS_FILE="/home/bitrix/www/bitrix/php_interface/cron_events.php"
HC_HTML_FILE="/home/bitrix/www/hc.html"
HC_PHP_FILE="/home/bitrix/www/hc.php"
GIT_IGNORE_FILE="/home/bitrix/www/.gitignore"

echo "Git container started. Run infinity loop..."

sync_file() {
    source_file="$1"
    target_file="$2"

    if [ ! -f "$source_file" ]; then
        return 0
    fi
    
    if [ ! -f "$target_file" ] || ! cmp -s "$source_file" "$target_file"; then
    if [ ! -f "$target_file" ]; then
      action="Создан"
    else
      action="Восстановлен"
    fi
    cp "$source_file" "$target_file"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $action: $target_file"
    fi
}

##  Base cycle
while true; do
  sync_file "/home/git/dbconn.php" "$DBCONN_FILE"
  sync_file "/home/git/.settings.php" "$SETTINGS_FILE"
  sync_file "/home/git/.settings_extra.php" "$SETTINGS_EXTRA_FILE"
  sync_file "/home/git/after_connect_d7.php" "$AFTER_CONNECT_D7_FILE"
  sync_file "/home/git/cron_events.php" "$CRON_EVENTS_FILE"
  sync_file "/home/git/.gitignore" "$GIT_IGNORE_FILE"
  sleep 60
done

{{- end -}}


##  Define a script for convenient push to git
{{/*
Git commit helper script
*/}}
{{- define "bitrix.gitCommitScript" -}}
#!/bin/sh
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <commit message>"
  exit 1
fi

git add .
git commit -m "$1"
git push origin {{ .Values.git.branch }}
{{- end }}

{{/*
Set permissions script
*/}}
{{- define "setPermission" -}}
##!/bin/sh
set -e
TARGET_DIR="/home/bitrix/www"
rm -rf "$TARGET_DIR/lost+found"
mkdir -p "$TARGET_DIR/bitrix/php_interface"
check_and_set_permissions() {
    dir="$1"
    if [ "$(stat -c %U:%G $dir)" != "bitrix:bitrix" ]; then
        chown bitrix:bitrix "$dir"
    fi
}
check_and_set_permissions "$TARGET_DIR"
check_and_set_permissions "$TARGET_DIR/bitrix"
check_and_set_permissions "$TARGET_DIR/bitrix/php_interface"
{{- end }}

{{/*
Get the TLS secret name
*/}}
{{- define "bitrix.tlsSecretName" -}}
{{- if .Values.tls.existingSecret -}}
    {{- .Values.tls.existingSecret -}}
{{- else -}}
    {{- printf "%s-cert" (include "bitrix.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Wait for certificate secret
*/}}
{{- define "bitrix.wait" -}}
until kubectl get secret {{ include "bitrix.tlsSecretName" . }} -n {{ .Release.Namespace }} 2>/dev/null; do
  echo "Waiting for certificate..."
  sleep 5
done
{{- end }}

{{/*
Pod scheduling configuration (nodeSelector, tolerations, affinity)
Usage: {{ include "chart.scheduling" (dict "values" .Values.main "context" .) | nindent 6 }}
*/}}
{{- define "chart.scheduling" -}}
{{- $values := .values -}}
{{- $context := .context -}}
{{- with $values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if $values.enabled }}
affinity:
  {{- if $values.nodeAffinity }}
  nodeAffinity:
    {{- tpl (toYaml $values.nodeAffinity) $context | nindent 4 }}
  {{- end }}
  {{- if $values.podAffinity }}
  podAffinity:
    {{- tpl (toYaml $values.podAffinity) $context | nindent 4 }}
  {{- end }}
  {{- if $values.podAntiAffinity }}
  podAntiAffinity:
    {{- tpl (toYaml $values.podAntiAffinity) $context | nindent 4 }}
  {{- end }}
{{- end }}
{{- end -}}


{{/*
Resolve PHP full tag (8.2.30)
Returns validated full tag or fallback
*/}}
{{- define "php.resolveFullTag" -}}
{{- $phpTag := .Values.php.tag | toString -}}
{{- $fallback := .Values.php.defaultTag -}}

{{- if not $phpTag -}}
{{- $fallback -}}
{{- else -}}
{{- $tagKey := printf "tag%s" (replace "." "" $phpTag) -}}
{{- $tagValue := index .Values.php $tagKey -}}
{{- if $tagValue -}}
{{- $phpTag -}}
{{- else -}}
{{- $fallback -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Resolve PHP minor tag (8.2)
Returns minor version
*/}}
{{- define "php.resolveTag" -}}
{{- $fullTag := include "php.resolveFullTag" . -}}
{{- $parts := splitList "." $fullTag -}}
{{- printf "%s.%s" (index $parts 0) (index $parts 1) -}}
{{- end -}}
