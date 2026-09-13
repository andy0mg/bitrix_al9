## Общее описание

Bitrix - решение для развертывания Bitrix environment в Yandex Managed Service for Kubernetes.

В зависимости от параметров заданных при установке чарта возможно установить так называемые **admin** или **prod** окружения.

Админское окружение предназначенно для развертывания продуктов Битрикс с нуля или из резервной копии, внесения изменений, тестирования и разработки.

Админское окружение должно иметь только одну реплику и не будет работать корректно если нарушить это ограничение.

Несмотря на основное предназначение админского окружения, полученную инсталляцию не запрещено использовать и в проде. 

Чтобы получить отказоустойчивое **prod** окружение потребуется собрать собственные образы на базе поставляемых чтобы включить в эти образы файлы Битрикс.

Продовое окружение может иметь больше одной реплики.

### Админское окружение поддерживает (можно включить или отключить):

- Клиент для работы с git
- Выполнение агентов в cron
- Сервер очередей Push and Pull
- Морфологический поиск Sphinx
- Иструменты для сбора метрик php и nginx

Продуктовое окружение поддерживает все возможности админского окружения, но не предназначено для внесения каких либо изменений.

Админское и продовое окружения совместно используют общие базу данных и S3-бакет.

### Требования:

- Kubernetes 1.28+</br>
- Helm 3.0+ </br>
- Cert-manager c плагином Yandex Cloud DNS ACME webhook</br>
- Container Storage Interface для S3 для работы с S3-совместимым хранилищем</br>
- MySQL, собственная инсталляция или управляемый [инстанс](https://yandex.cloud/ru/services/managed-mysql)</br>

### Установка админского окружения

Установка админского окружения из маркетплейса:

1. Укажите namespace для установки Bitrix.
2. Укажите название приложения.
3. Укажите размер тома для хранения файлов Битрикс.
4. Укажите класс хранилища для тома.
5. Укажите полное доменное имя проекта.
6. Укажите IP адрес балансировщика, если заранее его зарезервировали.
7. Выберите политику маршрутизации внешнего трафика.
8. Выберите "Использовать certmanager" чтобы автоматически получить сертификат от издателя Let's Encrypt. Для успешного получения сертификата [зарегистрируйте публичную доменную зону и делегируйте домен](https://yandex.cloud/ru/docs/dns/operations/zone-create-public). Сертификат Let's Encrypt® будет выписан для домена в этой зоне с прохождением проверки DNS-01.
9. Укажите адрес электронной почты для получения уведомлений от издателя Let's Encrypt.
10. Укажите имя ClusterIssuer или Issuer, который будет использоваться для автоматического получения SSL/TLS сертификатов.
11. Укажите имя секрета в котором расположен собственный сертификат если не планируете использоватиь certmanager. Необходимо создать Secret вида:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tls-secret
  namespace: default
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-certificate>
  tls.key: <base64-encoded-private-key>
```

12. Укажите "Использовать git" для работы с git-репозиторием.
13. Укажите параметры git репозитория:

 ```yaml
- Адрес git-репозитория, только доменное имя
- Ветку git-репозитория
- Git пользователя
- Git email
- В качестве git ssh ключа введите закодированное c помощью base64 содержимое ssh ключа
```

14. Укажите "Использовать cron" для запуска агентов в планировщике.
15. Укажите "Использовать push and pull" для работы сервера очередей push and pull.
16. В качестве скеретного ключа  push укажите результат выполнения команды:

```yaml
docker container run --rm --name push_server_key_generate alpine:3.21 sh -c "(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 128) && echo ''"
```

17. Укажите "Использовать sphinx" для работы полнотекстового поиска Sphinx.
18. Укажите "Храниnь кеш в redis" для хранения кеша в redis. Не рекомендуется включать в `admin` окружении.
19. Укажите "Включить метрики php" чтобы включить метрики php.
20. Укажите "Включить метрики nginx" чтобы включить метрики nginx.
21. Укажите класс хранилища для S3 в вашем кластере.
22. Укажите идентификатор ключа S3.
23. Укажите секретный ключ S3.
24. Укажите имя S3 бакета.
25. Укажите почтовые параметры для работы почты.
26. Укажите параметры подключения к базе данных.
27. Укажите версию php.
28. Укажите "Использовать bitrixsetup.php" для установки Битрикс с нуля.
29. Укажите "Использовать restore.php" для восстановления Битрикс из резервной копии.
30. Нажмите кнопку **Установить**.
31. Убедитесь, что все необходимые компоненты установились в кластере Kubernetes в указанном неймспейсе.
32. Откройте в браузере проект по указанному доменному имени и произведите инсталляцию продукта Битрикс с помощью установочного мастера.

Пример установки админского окружения из helm-chart:

```yaml
helm install bitrix-env -n bitrix-admin \
--create-namespace \
--set volumeSize="100Gi" \
--set fqdn="xxxxxxxxxxxxxxxxxxxx" \
--set loadBalancerIP="x.x.x.x" \
--set features.cron=true \
--set features.push=true \
--set features.sphinx=true \
--set features.phpExporter=true \
--set features.nginxExporter=true \
--set features.git=true \
--set git.repoUrl="xxxxxxxxxxxxxxxxx" \
--set git.name="xxxxxx" \
--set git.email="xxxxxxxxxxx" \
--set git.secret="xxxxxxxxxxxxx" \
--set s3.secret.accessKey="xxxxxxxxxxxxxx" \
--set s3.secret.secretKey="xxxxxxxxxxxxxx" \
--set s3.bucket="xxxxxxxxxxxxxx" \
--set msmtprc.host="xxxxxxxxx" \
--set msmtprc.port="xxx" \
--set msmtprc.user="xxxxxxxxxx" \
--set msmtprc.password="xxxxxxxxx" \
--set push.key="xxxxxxxxx" \
--set-json 'mysql={"host":"xxxxxxxx","login":"xxxxxx","password":"xxxxxx","database":"xxxxxxx"}' \
--set certmanager.enabled=false \
--set tls.existingSecret="bitrix-env-admin-cert" \
--set features.cache=false .
```

### Установка продового окружения.

1. Подготовьте Dockerfile:

```yaml
FROM cr.yandex/crpdm72eobaai6aa8ver/yandex-cloud/bitrix-env/bitrix/bitrix-admin-php:8.2.29
COPY --chown=bitrix:bitrix bitrix/ /home/bitrix/www
WORKDIR /home/bitrix/www
```

2. Соберите образ:

```yaml
docker build --platform linux/amd64 -f Dockerfile-php -t cr.yandex/crpnxxxxxxxxxxx/bitrix-prod-php:8.2.29 --no-cache .
```

Аналогично подготовьте образ для nginx, используя в качестве базового образа:

```yaml
FROM cr.yandex/crpdm72eobaai6aa8ver/yandex-cloud/bitrix-env/bitrix/bitrix-admin-nginx:1.28
```

3. Разверните продуктовое окружение:

```yaml
helm install bitrix-env -n bitrix-prod \
--create-namespace \
--set environment=prod \
--set replicaCount=3 \
--set fqdn="xxxxxxxxxxxxxxx" \
--set loadBalancerIP="xxxxxxxxxxxxxxx" \
--set features.cron=true \
--set features.push=true \
--set features.sphinx=true \
--set features.phpExporter=true \
--set features.nginxExporter=true \
--set features.git=true \
--set s3.secret.accessKey="xxxxxxxxxxxxxxx" \
--set s3.secret.secretKey="xxxxxxxxxxxxxxx" \
--set s3.bucket="xxxxxxxxxxxxxxx" \
--set msmtprc.host="xxxxxxxxxxxxxxx" \
--set msmtprc.port="xxxxxxxxxxxxxxx" \
--set msmtprc.user="xxxxxxxxxxxxxxx" \
--set msmtprc.password="xxxxxxxxxxxxxxx" \
--set push.key="xxxxxxxxxxxxxxx" \
--set-json 'mysql={"host":"c-xxxxxxxxxxxxxxx","login":"xxxxxxxxxxxxxxx","password":"xxxxxxxxxxxxxxx","database":"xxxxxxxxxxxxxxx"}' \
--set php.image="cr.yandex/crpnxxxxxxxxxxx/bitrix-prod-php:8.2.29" \
--set nginx.image="cr.yandex/crpnxxxxxxxxxxx/bitrix-prod-nginx:1.28" \
--set tls.existingSecret="bitrix-env-prod-cert" \
--set certmanager.enabled=false .
```

Обратите внимание, вы должны использовать одинаковые параметры для базы данных и s3-бакета.

Убедитесь, что все необходимые компоненты установились в кластере Kubernetes в указанном неймспейсе.

На этом установка продового окружения завершена.