Скопируйте сертификаты СО СТАРОГО сервера на НОВЫЙ.

На старом (10.21.62.180):
  ls -la /etc/nginx/ssl/

Ожидаемые файлы (из nginx -T):
  petrovich.tech.pem / petrovich.tech.key
  petlocal.ru2025.pem / petlocal.ru2025.key
  cert.pem / cert.key          # default SSL
  dhparam.pem                  # опционально

С нового (10.254.61.6), от root:

  mkdir -p /etc/nginx/ssl
  scp root@10.21.62.180:/etc/nginx/ssl/petrovich.tech.pem \
      root@10.21.62.180:/etc/nginx/ssl/petrovich.tech.key \
      root@10.21.62.180:/etc/nginx/ssl/petlocal.ru2025.pem \
      root@10.21.62.180:/etc/nginx/ssl/petlocal.ru2025.key \
      root@10.21.62.180:/etc/nginx/ssl/cert.pem \
      root@10.21.62.180:/etc/nginx/ssl/cert.key \
      root@10.21.62.180:/etc/nginx/ssl/dhparam.pem \
      /etc/nginx/ssl/

  chmod 640 /etc/nginx/ssl/*.key
  chmod 644 /etc/nginx/ssl/*.pem

Либо положите копию каталога рядом с плейбуком и задайте в local.yml:
  bitrix_enable_custom_sites: true
  bitrix_ssl_cert_source: /path/to/ssl-backup

НЕ коммитьте ключи в git.
