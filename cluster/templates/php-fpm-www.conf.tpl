; Bitrix Environment 9 — PHP-FPM pool (rendered into /etc/php-fpm.d/www.conf).
; Placeholders substituted from cluster.env by cluster_render_template.
[www]
user = @PHP_FPM_USER@
group = @PHP_FPM_GROUP@

listen = @PHP_FPM_SOCKET@
listen.owner = @PHP_FPM_LISTEN_OWNER@
listen.group = @PHP_FPM_LISTEN_GROUP@
listen.mode = 0660

pm = dynamic
pm.max_children = @PHP_FPM_MAX_CHILDREN@
pm.start_servers = @PHP_FPM_START_SERVERS@
pm.min_spare_servers = @PHP_FPM_MIN_SPARE_SERVERS@
pm.max_spare_servers = @PHP_FPM_MAX_SPARE_SERVERS@
pm.max_requests = @PHP_FPM_MAX_REQUESTS@

request_terminate_timeout = 0
catch_workers_output = yes
clear_env = no

php_admin_value[error_log] = /var/log/php-fpm/www-error.log
php_admin_flag[log_errors] = on
php_value[session.save_handler] = files
php_value[session.save_path] = /var/lib/php/session
php_value[soap.wsdl_cache_dir] = /var/lib/php/wsdlcache
