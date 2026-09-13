# Bitrix Environment 9 — memcached (rendered into /etc/sysconfig/memcached).
# Placeholders substituted from cluster.env by cluster_render_template.
PORT="@MEMCACHED_PORT@"
USER="memcached"
MAXCONN="@MEMCACHED_MAXCONN@"
CACHESIZE="@MEMCACHED_CACHESIZE@"
OPTIONS="-l @MEMCACHED_BIND@"
